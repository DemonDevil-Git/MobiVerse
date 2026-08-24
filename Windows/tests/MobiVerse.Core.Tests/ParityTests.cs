using MobiVerse.Core;
using System.IO.Compression;
using System.Text;
using Xunit;

namespace MobiVerse.Core.Tests;

public sealed class BrowserDownloadPolicyTests
{
    [Fact] public void DownloadsMainFramePdfWhenEnabled() => Assert.True(Should("https://example.test/signed?id=1", "application/pdf", true, true));
    [Fact] public void LeavesMainFramePdfInBrowserWhenDisabled() => Assert.False(Should("https://example.test/file.pdf", "application/pdf", true, false));
    [Fact] public void LeavesEmbeddedPdfInBrowser() => Assert.False(Should("https://example.test/file.pdf", "application/pdf", false, true));
    [Fact] public void DownloadsBookMimeType() => Assert.True(Should("https://example.test/book", "application/epub+zip", true, false));
    [Fact] public void DownloadsBookFileExtension() => Assert.True(Should("https://example.test/book.azw3", "application/octet-stream", true, false));
    [Fact] public void DownloadsAttachment() => Assert.True(BrowserDownloadPolicy.ShouldDownload(new(new("https://example.test/book"), "text/plain", "book", "attachment", true, true), false));
    private static bool Should(string url, string mime, bool main, bool pdf) => BrowserDownloadPolicy.ShouldDownload(new(new(url), mime, null, null, main, true), pdf);
}

public sealed class DownloadedBookValidatorTests : IDisposable
{
    private readonly string _root = TestData.Directory();
    [Fact] public void RecognizesPdfWithoutFilenameExtension() { var path = Bytes("download", "%PDF-1.7\n"); Assert.Equal("pdf", DownloadedBookValidator.ValidatedExtension(path, "")); }
    [Fact] public void RecognizesMobiHeader() { var bytes = new byte[80]; Encoding.ASCII.GetBytes("BOOKMOBI").CopyTo(bytes, 60); var path = Bytes("download.bin", bytes); Assert.Equal("mobi", DownloadedBookValidator.ValidatedExtension(path, "mobi")); }
    [Fact] public void RecognizesZipArchive() { var path = Path.Combine(_root, "book.bin"); using (ZipFile.Open(path, ZipArchiveMode.Create)) { } Assert.Equal("zip", DownloadedBookValidator.ValidatedExtension(path, "bin")); }
    [Fact] public void RejectsHtmlDisguisedAsBook() { var path = Bytes("book.epub", "<!doctype html><html></html>"); Assert.Throws<DownloadedBookValidationException>(() => DownloadedBookValidator.ValidatedExtension(path, "epub")); }
    [Fact] public void RejectsExecutableDisguisedAsBook() { var path = Bytes("book.pdf", new byte[] { 0x4d, 0x5a, 1, 2 }); Assert.Throws<DownloadedBookValidationException>(() => DownloadedBookValidator.ValidatedExtension(path, "pdf")); }
    private string Bytes(string name, string value) => Bytes(name, Encoding.ASCII.GetBytes(value));
    private string Bytes(string name, byte[] value) { var path = Path.Combine(_root, name); File.WriteAllBytes(path, value); return path; }
    public void Dispose() => TestData.Delete(_root);
}

public sealed class ClassifierParityTests
{
    [Fact] public void EpubWithSubstantialTextIsText() => Assert.Equal(BookContentKind.Text, BookClassifier.ClassifyEpubTextCounts([500, 900, 800, 12]).Kind);
    [Fact] public void EpubWithMixedShortSectionsIsUncertain() => Assert.Equal(BookContentKind.Uncertain, BookClassifier.ClassifyEpubTextCounts([20, 800, 30, 40]).Kind);
    [Fact] public void SelectablePdfIsText() => Assert.Equal(BookContentKind.Text, BookClassifier.ClassifyPdfTextCounts([600, 700, 900, 1000]).Kind);
    [Fact] public void ScannedPdfIsComic() => Assert.Equal(BookContentKind.Comic, BookClassifier.ClassifyPdfTextCounts([0, 2, 0, 12]).Kind);
    [Fact] public void MixedPdfIsUncertain() => Assert.Equal(BookContentKind.Uncertain, BookClassifier.ClassifyPdfTextCounts([0, 120, 800, 50]).Kind);
}

public sealed class TextEpubPostProcessorTests : IDisposable
{
    private readonly string _root = TestData.Directory();
    [Fact] public void PreservesRubyMarkup() { var epub = BuildDefectiveTextEpub(); new TextEpubPostProcessor().Process(epub); Assert.Contains("<ruby>", Extract(epub, "OEBPS/page.xhtml")); }
    [Fact] public void RepairsInvalidIdentifiersAndReferences() { var epub = BuildDefectiveTextEpub(); var result = new TextEpubPostProcessor().Process(epub); var page = Extract(epub, "OEBPS/page.xhtml"); Assert.True(result.RepairedIdentifierCount > 0); Assert.Contains("id=\"mv-12-bad\"", page); Assert.Contains("#mv-12-bad", page); }
    [Fact] public void RemovesBrokenStyleReferences() { var epub = BuildDefectiveTextEpub(); var result = new TextEpubPostProcessor().Process(epub); Assert.True(result.RemovedBrokenResourceCount >= 2); Assert.DoesNotContain("missing.css", Extract(epub, "OEBPS/page.xhtml")); Assert.DoesNotContain("missing.woff", Extract(epub, "OEBPS/style.css")); }
    [Fact] public void RepairsNavigationOrder() { var epub = BuildDefectiveTextEpub(); var result = new TextEpubPostProcessor().Process(epub); Assert.True(result.ReorderedNavigationCount > 0); Assert.Contains("playOrder=\"1\"", Extract(epub, "OEBPS/toc.ncx")); }

    private string BuildDefectiveTextEpub()
    {
        var path = Path.Combine(_root, $"defective-{Guid.NewGuid():N}.epub");
        using var archive = ZipFile.Open(path, ZipArchiveMode.Create);
        Add(archive, "mimetype", "application/epub+zip");
        Add(archive, "OEBPS/page.xhtml", "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><link rel=\"stylesheet\" href=\"missing.css\"/></head><body><p id=\"12 bad\"><a href=\"#12 bad\"><ruby>漢<rt>かん</rt></ruby></a></p></body></html>");
        Add(archive, "OEBPS/style.css", "@font-face { font-family:x; src:url('missing.woff'); } p { color:#222; }");
        Add(archive, "OEBPS/toc.ncx", "<ncx><navMap><navPoint playOrder=\"7\"/><navPoint playOrder=\"3\"/></navMap></ncx>");
        return path;
    }
    private string Extract(string epub, string entryName) { using var archive = ZipFile.OpenRead(epub); using var reader = new StreamReader(archive.GetEntry(entryName)!.Open()); return reader.ReadToEnd(); }
    private static void Add(ZipArchive archive, string name, string value) { var entry = archive.CreateEntry(name); using var writer = new StreamWriter(entry.Open(), new UTF8Encoding(false)); writer.Write(value); }
    public void Dispose() => TestData.Delete(_root);
}

public sealed class ReadingPositionParityTests : IDisposable
{
    private readonly string _root = TestData.Directory();
    [Fact] public void SavesSectionAndPage() { var store = new ReadingPositionStore(Path.Combine(_root, "positions.json")); store.SavePosition("C:\\book.epub", new(3, 8)); Assert.Equal(new PreviewReadingPosition(3, 8), store.GetPosition("C:\\book.epub", true)); }
    [Fact] public void MigratesLegacyValueAsSection() { var file = Path.Combine(_root, "positions.json"); var key = Path.GetFullPath("C:\\book.epub").TrimEnd(Path.DirectorySeparatorChar).ToUpperInvariant(); File.WriteAllText(file, $"{{\"{key.Replace("\\", "\\\\")}\":4}}"); var position = new ReadingPositionStore(file).GetPosition("C:\\book.epub", true); Assert.Equal(4, position.SectionIndex); Assert.Equal(0, position.PageIndex); }
    public void Dispose() => TestData.Delete(_root);
}

public sealed class PreviewParityTests : IDisposable
{
    private readonly string _root = TestData.Directory();
    [Fact] public void ReturnsEveryTextSpineSection() { var epub = BuildTextEpub(false); var book = new EpubPreviewParser().Parse(epub, Path.Combine(_root, "sections")); Assert.Equal(EpubPreviewKind.Web, book.Kind); Assert.Equal(2, book.SpineDocumentPaths.Count); }
    [Fact] public void XhtmlWithVisibleTextIsNotMisclassifiedAsImagePage() { var epub = BuildTextEpub(true); var book = new EpubPreviewParser().Parse(epub, Path.Combine(_root, "mixed")); Assert.Equal(EpubPreviewKind.Web, book.Kind); }
    private string BuildTextEpub(bool withImages)
    {
        var path = Path.Combine(_root, $"book-{Guid.NewGuid():N}.epub");
        using var archive = ZipFile.Open(path, ZipArchiveMode.Create);
        Add(archive, "META-INF/container.xml", "<container xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\"><rootfiles><rootfile full-path=\"OEBPS/content.opf\"/></rootfiles></container>");
        Add(archive, "OEBPS/content.opf", "<package xmlns=\"http://www.idpf.org/2007/opf\"><manifest><item id=\"a\" href=\"a.xhtml\" media-type=\"application/xhtml+xml\"/><item id=\"b\" href=\"b.xhtml\" media-type=\"application/xhtml+xml\"/></manifest><spine><itemref idref=\"a\"/><itemref idref=\"b\"/></spine></package>");
        var body = withImages ? "Text<img src=\"page.png\"/>" : "A substantial text section";
        Add(archive, "OEBPS/a.xhtml", $"<html xmlns=\"http://www.w3.org/1999/xhtml\"><body>{body}</body></html>");
        Add(archive, "OEBPS/b.xhtml", $"<html xmlns=\"http://www.w3.org/1999/xhtml\"><body>{body}</body></html>");
        return path;
    }
    private static void Add(ZipArchive archive, string name, string value) { var entry = archive.CreateEntry(name); using var writer = new StreamWriter(entry.Open(), new UTF8Encoding(false)); writer.Write(value); }
    public void Dispose() => TestData.Delete(_root);
}

public sealed class ComicMetadataParityTests : IDisposable
{
    private readonly string _root = TestData.Directory();
    [Fact] public void WritesLtrMetadataWhenRequested() { var opf = Build(EpubReadingDirection.LeftToRight); Assert.Contains("page-progression-direction=\"ltr\"", opf); Assert.Contains("primary-writing-mode\" content=\"horizontal-lr\"", opf); }
    [Fact] public void PlacesSvgOnlyOnManifestPageItems() { var opf = Build(EpubReadingDirection.RightToLeft); Assert.Contains("media-type=\"application/xhtml+xml\" properties=\"svg\"", opf); Assert.DoesNotContain("rendition:layout-pre-paginated svg", opf); Assert.DoesNotContain("properties=\"\"", opf); Assert.Equal(1, Count(opf, "property=\"dcterms:modified\"")); }
    private string Build(EpubReadingDirection direction) { var a = TestData.Png(_root, "a.png", 100, 200); var b = TestData.Png(_root, "b.png", 100, 200); var epub = Path.Combine(_root, $"{direction}.epub"); new EpubArchiveService().BuildFixedLayout("Book", [a, b], epub, direction); var extract = Path.Combine(_root, direction.ToString()); EpubPathSecurity.ExtractSafely(epub, extract); return File.ReadAllText(Path.Combine(extract, "OEBPS", "content.opf")); }
    private static int Count(string value, string token) => (value.Length - value.Replace(token, "").Length) / token.Length;
    public void Dispose() => TestData.Delete(_root);
}
