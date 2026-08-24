using System.IO.Compression;
using System.Security;
using System.Text;

namespace MobiVerse.Core;

public sealed class EpubArchiveService
{
    private static readonly HashSet<string> ImageExtensions = new(StringComparer.OrdinalIgnoreCase)
    { ".jpg", ".jpeg", ".png", ".gif", ".webp" };

    public string ProcessComicEpub(string epubPath, EpubReadingDirection readingDirection = EpubReadingDirection.RightToLeft)
    {
        var work = NewTemporaryDirectory("MobiVersePostProcess");
        try
        {
            EpubPathSecurity.ExtractSafely(epubPath, work);
            var images = Directory.EnumerateFiles(work, "*", SearchOption.AllDirectories)
                .Where(path => ImageExtensions.Contains(Path.GetExtension(path)))
                .OrderBy(path => NaturalKey(Path.GetRelativePath(work, path)), StringComparer.OrdinalIgnoreCase)
                .ToArray();
            var title = ReadTitle(work) ?? Path.GetFileNameWithoutExtension(epubPath);
            return BuildFixedLayout(title, images, epubPath, readingDirection);
        }
        finally { TryDelete(work); }
    }

    public string BuildFixedLayout(
        string title,
        IReadOnlyList<string> imagePaths,
        string outputPath,
        EpubReadingDirection readingDirection = EpubReadingDirection.RightToLeft)
    {
        if (imagePaths.Count == 0) throw new InvalidDataException("No image pages were found.");
        var work = NewTemporaryDirectory("MobiVerseRebuiltEPUB");
        try
        {
            var metaInf = Directory.CreateDirectory(Path.Combine(work, "META-INF")).FullName;
            var oebps = Directory.CreateDirectory(Path.Combine(work, "OEBPS")).FullName;
            var images = Directory.CreateDirectory(Path.Combine(oebps, "images")).FullName;
            var pages = Directory.CreateDirectory(Path.Combine(oebps, "pages")).FullName;
            File.WriteAllText(Path.Combine(work, "mimetype"), "application/epub+zip", new UTF8Encoding(false));
            File.WriteAllText(Path.Combine(metaInf, "container.xml"), ContainerXml, new UTF8Encoding(false));
            File.WriteAllText(Path.Combine(metaInf, "com.apple.ibooks.display-options.xml"), DisplayOptions, new UTF8Encoding(false));

            var manifest = new StringBuilder();
            var spine = new StringBuilder();
            var nav = new StringBuilder();
            for (var index = 0; index < imagePaths.Count; index++)
            {
                var number = index + 1;
                var extension = NormalizeImageExtension(Path.GetExtension(imagePaths[index]));
                var imageName = $"page-{number:00000}{extension}";
                var pageName = $"page-{number:00000}.xhtml";
                File.Copy(imagePaths[index], Path.Combine(images, imageName), true);
                var dimensions = ImageDimensions.Read(imagePaths[index]);
                File.WriteAllText(
                    Path.Combine(pages, pageName),
                    PageXhtml(title, number, imageName, dimensions.Width, dimensions.Height),
                    new UTF8Encoding(false));
                var coverProperty = number == 1 ? " properties=\"cover-image\"" : string.Empty;
                manifest.AppendLine($"    <item id=\"image-{number}\" href=\"images/{imageName}\" media-type=\"{MediaType(extension)}\"{coverProperty}/>");
                manifest.AppendLine($"    <item id=\"page-{number}\" href=\"pages/{pageName}\" media-type=\"application/xhtml+xml\" properties=\"svg\"/>");
                spine.AppendLine($"    <itemref idref=\"page-{number}\" properties=\"rendition:layout-pre-paginated\"/>");
                nav.AppendLine($"      <li><a href=\"pages/{pageName}\">Page {number}</a></li>");
            }
            File.WriteAllText(Path.Combine(oebps, "nav.xhtml"), NavXhtml(title, nav.ToString()), new UTF8Encoding(false));
            File.WriteAllText(Path.Combine(oebps, "content.opf"), Opf(title, manifest.ToString(), spine.ToString(), readingDirection), new UTF8Encoding(false));

            var replacement = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(outputPath))!, $".{Path.GetFileNameWithoutExtension(outputPath)}-{Guid.NewGuid():N}.epub");
            using (var stream = new FileStream(replacement, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None))
            using (var archive = new ZipArchive(stream, ZipArchiveMode.Create))
            {
                AddFile(archive, Path.Combine(work, "mimetype"), "mimetype", CompressionLevel.NoCompression);
                foreach (var file in Directory.EnumerateFiles(metaInf, "*", SearchOption.AllDirectories))
                    AddFile(archive, file, Path.GetRelativePath(work, file).Replace('\\', '/'), CompressionLevel.NoCompression);
                foreach (var file in Directory.EnumerateFiles(oebps, "*", SearchOption.AllDirectories))
                    AddFile(archive, file, Path.GetRelativePath(work, file).Replace('\\', '/'), CompressionLevel.NoCompression);
            }
            File.Move(replacement, outputPath, true);
            var directionText = readingDirection == EpubReadingDirection.RightToLeft ? "right-to-left" : "left-to-right";
            return $"Comic EPUB post-processing\n--------------------------\nPages: {imagePaths.Count}\nImages: {imagePaths.Count}\nFixed layout: yes\nReading direction: {directionText}";
        }
        finally { TryDelete(work); }
    }

    private static string? ReadTitle(string root)
    {
        var opf = Directory.EnumerateFiles(root, "*.opf", SearchOption.AllDirectories).FirstOrDefault();
        if (opf is null) return null;
        try
        {
            var document = System.Xml.Linq.XDocument.Load(opf);
            return document.Descendants().FirstOrDefault(element => element.Name.LocalName == "title")?.Value.Trim();
        }
        catch { return null; }
    }

    private static void AddFile(ZipArchive archive, string path, string entryName, CompressionLevel level)
    {
        var entry = archive.CreateEntry(entryName, level);
        entry.LastWriteTime = new DateTimeOffset(1980, 1, 1, 0, 0, 0, TimeSpan.Zero);
        using var input = File.OpenRead(path);
        using var output = entry.Open();
        input.CopyTo(output);
    }

    private static string NewTemporaryDirectory(string name)
    {
        var path = Path.Combine(Path.GetTempPath(), name, Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(path);
        return path;
    }

    private static void TryDelete(string path) { try { Directory.Delete(path, true); } catch { } }
    private static string NaturalKey(string value) => System.Text.RegularExpressions.Regex.Replace(value, @"\d+", match => match.Value.PadLeft(16, '0'));
    private static string NormalizeImageExtension(string extension) => extension.Equals(".jpeg", StringComparison.OrdinalIgnoreCase) ? ".jpg" : extension.ToLowerInvariant();
    private static string MediaType(string extension) => extension switch { ".png" => "image/png", ".gif" => "image/gif", ".webp" => "image/webp", _ => "image/jpeg" };
    private static string Escape(string value) => SecurityElement.Escape(value) ?? string.Empty;

    private static string PageXhtml(string title, int number, string imageName, int width, int height) => $$"""
<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>{{Escape(title)}} – Page {{number}}</title><meta name="viewport" content="width={{width}},height={{height}}"/><style>html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:#000}svg{display:block;width:100%;height:100%}</style></head><body><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {{width}} {{height}}" preserveAspectRatio="xMidYMid meet"><image href="../images/{{imageName}}" width="{{width}}" height="{{height}}"/></svg></body></html>
""";

    private static string NavXhtml(string title, string items) => $$"""
<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>{{Escape(title)}}</title></head><body><nav epub:type="toc" id="toc"><h1>{{Escape(title)}}</h1><ol>
{{items}}    </ol></nav></body></html>
""";

    private static string Opf(string title, string manifest, string spine, EpubReadingDirection readingDirection)
    {
        var progression = readingDirection == EpubReadingDirection.RightToLeft ? "rtl" : "ltr";
        var writingMode = readingDirection == EpubReadingDirection.RightToLeft ? "vertical-rl" : "horizontal-lr";
        var language = readingDirection == EpubReadingDirection.RightToLeft ? "ja" : "en";
        return $$"""
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id" prefix="rendition: http://www.idpf.org/vocab/rendition/#"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">urn:uuid:{{Guid.NewGuid()}}</dc:identifier><dc:title>{{Escape(title)}}</dc:title><dc:language>{{language}}</dc:language><meta property="dcterms:modified">{{DateTime.UtcNow:yyyy-MM-ddTHH:mm:ssZ}}</meta><meta property="rendition:layout">pre-paginated</meta><meta property="rendition:orientation">auto</meta><meta property="rendition:spread">none</meta><meta name="primary-writing-mode" content="{{writingMode}}"/><meta name="fixed-layout" content="true"/><meta name="book-type" content="comic"/><meta name="zero-gutter" content="true"/></metadata><manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
{{manifest}}  </manifest><spine page-progression-direction="{{progression}}">
{{spine}}  </spine></package>
""";
    }

    private const string ContainerXml = """<?xml version="1.0" encoding="UTF-8"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>""";
    private const string DisplayOptions = """<?xml version="1.0" encoding="UTF-8"?><display_options><platform name="*"><option name="fixed-layout">true</option><option name="open-to-spread">false</option><option name="specified-fonts">false</option></platform></display_options>""";
}
