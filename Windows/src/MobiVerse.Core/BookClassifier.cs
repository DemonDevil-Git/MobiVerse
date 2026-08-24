using System.IO.Compression;
using System.Net;
using System.Text.RegularExpressions;

namespace MobiVerse.Core;

public sealed class BookClassifier(IProcessRunner runner, IToolchainLocator locator)
{
    private static readonly HashSet<string> ImageExtensions = new(StringComparer.OrdinalIgnoreCase)
    { ".jpg", ".jpeg", ".png", ".gif", ".webp", ".avif" };

    public async Task<ClassificationResult> ClassifyAsync(string path, CancellationToken cancellationToken = default)
    {
        return Path.GetExtension(path).ToLowerInvariant() switch
        {
            ".cbz" or ".cbr" => new(BookContentKind.Comic, 1, "Comic archive format"),
            ".zip" => ClassifyZip(path),
            ".epub" => ClassifyEpub(path),
            ".pdf" => await ClassifyPdfAsync(path, cancellationToken).ConfigureAwait(false),
            ".mobi" or ".azw" or ".azw3" => await ClassifyCalibreBookAsync(path, cancellationToken).ConfigureAwait(false),
            _ => throw new NotSupportedException("Unsupported book format.")
        };
    }

    public static ClassificationResult ClassifyEpubTextCounts(IReadOnlyList<int> counts)
    {
        var textPages = counts.Count(value => value >= 200);
        var ratio = counts.Count == 0 ? 0 : (double)textPages / counts.Count;
        if (ratio >= .6 && Median(counts) >= 200)
            return new(BookContentKind.Text, Math.Min(.98, .7 + ratio * .25), $"{textPages} of {counts.Count} spine sections contain substantial text");
        return new(BookContentKind.Uncertain, .45, "The book mixes image pages and short text sections");
    }

    public static ClassificationResult ClassifyPdfTextCounts(IReadOnlyList<int> counts)
    {
        if (counts.Count == 0) return new(BookContentKind.Uncertain, 0, "PDF contains no readable pages");
        var richPages = counts.Count(value => value >= 200);
        var readablePages = counts.Count(value => value >= 80);
        var richRatio = (double)richPages / counts.Count;
        var readableRatio = (double)readablePages / counts.Count;
        if (richRatio >= .6 && Median(counts) >= 400)
            return new(BookContentKind.Text, Math.Min(.96, .72 + richRatio * .24), "Most sampled PDF pages contain selectable text");
        if (readableRatio <= .2)
            return new(BookContentKind.Comic, .9, "PDF pages are predominantly images or scans");
        return new(BookContentKind.Uncertain, .45, "PDF contains a mixture of text and image-heavy pages");
    }

    private static ClassificationResult ClassifyZip(string path)
    {
        using var archive = ZipFile.OpenRead(path);
        var files = archive.Entries.Where(entry => !string.IsNullOrEmpty(entry.Name)).ToArray();
        if (files.Length == 0) throw new InvalidDataException("The archive is empty or unreadable.");
        var imageCount = files.Count(entry => ImageExtensions.Contains(Path.GetExtension(entry.Name)));
        var ratio = (double)imageCount / files.Length;
        return imageCount >= 2 && ratio >= .8
            ? new(BookContentKind.Comic, Math.Min(1, ratio), $"{imageCount} of {files.Length} archive files are images")
            : new(BookContentKind.Uncertain, .35, "Archive is not predominantly image pages");
    }

    private static ClassificationResult ClassifyEpub(string path)
    {
        var extraction = TemporaryDirectory("MobiVerseClassification");
        try
        {
            var book = new EpubPreviewParser().Parse(path, extraction);
            if (book.Kind == EpubPreviewKind.ImagePages)
                return new(BookContentKind.Comic, .95, $"{book.ImagePages.Count} spine items are full-page images");
            return ClassifyEpubTextCounts(book.SpineDocumentPaths.Select(VisibleCharacterCount).ToArray());
        }
        finally { TryDelete(extraction); }
    }

    private async Task<ClassificationResult> ClassifyPdfAsync(string path, CancellationToken cancellationToken)
    {
        var ebookConvert = locator.Inspect().EbookConvertPath;
        if (ebookConvert is null)
            return new(BookContentKind.Uncertain, .35, "PDF text detection requires the bundled conversion tools");

        var directory = TemporaryDirectory("MobiVersePDFClassification");
        try
        {
            var textPath = Path.Combine(directory, "sample.txt");
            var result = await runner.RunAsync(ebookConvert, [path, textPath], cancellationToken: cancellationToken).ConfigureAwait(false);
            if (result.ExitCode != 0 || !File.Exists(textPath))
                return new(BookContentKind.Uncertain, .35, "PDF text could not be inspected automatically");
            var pages = File.ReadAllText(textPath).Split('\f')
                .Select(text => text.Count(character => !char.IsWhiteSpace(character))).ToArray();
            if (pages.Length == 1)
            {
                var total = pages[0];
                return total >= 1200
                    ? new(BookContentKind.Text, .82, "PDF contains substantial selectable text")
                    : new(BookContentKind.Comic, .76, "PDF contains little selectable text and appears image-based");
            }
            return ClassifyPdfTextCounts(Sample(pages, 20));
        }
        finally { TryDelete(directory); }
    }

    private async Task<ClassificationResult> ClassifyCalibreBookAsync(string path, CancellationToken cancellationToken)
    {
        var ebookConvert = locator.Inspect().EbookConvertPath;
        if (ebookConvert is null) throw new InvalidOperationException("Calibre is required to inspect this book.");
        var directory = TemporaryDirectory("MobiVerseNeutralClassification");
        try
        {
            var epubPath = Path.Combine(directory, "neutral.epub");
            var result = await runner.RunAsync(ebookConvert,
                [path, epubPath, "--preserve-cover-aspect-ratio", "--disable-font-rescaling", "--pretty-print", "--epub-version=3"],
                cancellationToken: cancellationToken).ConfigureAwait(false);
            if (result.ExitCode != 0) throw new InvalidDataException("The book could not be inspected.");
            return ClassifyEpub(epubPath);
        }
        finally { TryDelete(directory); }
    }

    private static int VisibleCharacterCount(string path)
    {
        try
        {
            var text = File.ReadAllText(path);
            text = Regex.Replace(text, @"<script\b[^>]*>[\s\S]*?</script>", "", RegexOptions.IgnoreCase);
            text = Regex.Replace(text, @"<style\b[^>]*>[\s\S]*?</style>", "", RegexOptions.IgnoreCase);
            text = WebUtility.HtmlDecode(Regex.Replace(text, @"<[^>]+>", " "));
            return text.Count(character => !char.IsWhiteSpace(character));
        }
        catch { return 0; }
    }

    private static IReadOnlyList<int> Sample(IReadOnlyList<int> values, int maximum)
    {
        if (values.Count <= maximum) return values;
        return Enumerable.Range(0, maximum)
            .Select(index => values[(int)Math.Round((double)index * (values.Count - 1) / (maximum - 1))]).ToArray();
    }

    private static int Median(IReadOnlyList<int> values) =>
        values.Count == 0 ? 0 : values.OrderBy(value => value).ElementAt(values.Count / 2);

    private static string TemporaryDirectory(string name)
    {
        var path = Path.Combine(Path.GetTempPath(), name, Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(path);
        return path;
    }

    private static void TryDelete(string path) { try { Directory.Delete(path, true); } catch { } }
}
