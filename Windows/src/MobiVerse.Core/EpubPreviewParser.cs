using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace MobiVerse.Core;

public sealed class EpubPreviewParser
{
    private static readonly HashSet<string> ImageExtensions = new(StringComparer.OrdinalIgnoreCase)
    { ".jpg", ".jpeg", ".png", ".gif", ".webp" };

    public EpubPreviewBook Parse(string epubPath, string extractionDirectory)
    {
        EpubPathSecurity.ExtractSafely(epubPath, extractionDirectory);
        var opfPath = FindPackageDocument(extractionDirectory);
        var document = XDocument.Load(opfPath, LoadOptions.PreserveWhitespace);
        var packageDirectory = Path.GetDirectoryName(opfPath)!;
        var title = document.Descendants().FirstOrDefault(element => element.Name.LocalName == "title")?.Value.Trim();
        if (string.IsNullOrWhiteSpace(title)) title = Path.GetFileNameWithoutExtension(epubPath);

        var manifest = document.Descendants()
            .Where(element => element.Name.LocalName == "item")
            .Where(element => element.Attribute("id") is not null && element.Attribute("href") is not null)
            .ToDictionary(
                element => element.Attribute("id")!.Value,
                element => new ManifestItem(
                    element.Attribute("href")!.Value,
                    element.Attribute("media-type")?.Value ?? string.Empty),
                StringComparer.Ordinal);
        var spine = document.Descendants()
            .Where(element => element.Name.LocalName == "itemref")
            .Select(element => element.Attribute("idref")?.Value)
            .Where(value => value is not null && manifest.ContainsKey(value))
            .Select(value => manifest[value!])
            .ToArray();
        var direction = document.Descendants().FirstOrDefault(element => element.Name.LocalName == "spine")?
            .Attribute("page-progression-direction")?.Value == "rtl"
            ? EpubReadingDirection.RightToLeft
            : EpubReadingDirection.LeftToRight;

        var pages = new List<EpubImagePreviewPage>();
        for (var index = 0; index < spine.Length; index++)
        {
            var itemPath = EpubPathSecurity.Resolve(spine[index].Href, packageDirectory, extractionDirectory);
            if (itemPath is null || !File.Exists(itemPath)) continue;
            var imagePath = spine[index].MediaType.StartsWith("image/", StringComparison.OrdinalIgnoreCase)
                ? itemPath
                : ImageReferencedByHtml(itemPath, extractionDirectory);
            if (imagePath is null || !File.Exists(imagePath) || !ImageExtensions.Contains(Path.GetExtension(imagePath))) continue;
            var dimensions = ImageDimensions.Read(imagePath);
            pages.Add(new($"page-{index + 1:00000}", $"Page {index + 1}", imagePath, dimensions.Width, dimensions.Height));
        }

        if (pages.Count >= 2 && pages.Count >= Math.Max(1, spine.Length * 4 / 5))
            return new(title, epubPath, extractionDirectory, packageDirectory, direction, EpubPreviewKind.ImagePages, pages, null);

        var webItem = spine.FirstOrDefault(item => item.MediaType.Contains("html", StringComparison.OrdinalIgnoreCase));
        var startPath = webItem is null ? null : EpubPathSecurity.Resolve(webItem.Href, packageDirectory, extractionDirectory);
        if (startPath is null || !File.Exists(startPath)) throw new InvalidDataException("No readable pages were found in this EPUB.");
        return new(title, epubPath, extractionDirectory, packageDirectory, direction, EpubPreviewKind.Web, [], startPath);
    }

    public string? ExtractCover(string epubPath, string extractionDirectory)
    {
        EpubPathSecurity.ExtractSafely(epubPath, extractionDirectory);
        var opfPath = FindPackageDocument(extractionDirectory);
        var document = XDocument.Load(opfPath);
        var packageDirectory = Path.GetDirectoryName(opfPath)!;
        var items = document.Descendants().Where(element => element.Name.LocalName == "item").ToArray();
        var coverId = document.Descendants().FirstOrDefault(element =>
            element.Name.LocalName == "meta" && element.Attribute("name")?.Value == "cover")?.Attribute("content")?.Value;
        var item = items.FirstOrDefault(element => element.Attribute("properties")?.Value.Split(' ').Contains("cover-image") == true)
            ?? items.FirstOrDefault(element => element.Attribute("id")?.Value == coverId)
            ?? items.FirstOrDefault(element => element.Attribute("id")?.Value.Contains("cover", StringComparison.OrdinalIgnoreCase) == true);
        var href = item?.Attribute("href")?.Value;
        var path = href is null ? null : EpubPathSecurity.Resolve(href, packageDirectory, extractionDirectory);
        return path is not null && File.Exists(path) ? path : null;
    }

    private static string FindPackageDocument(string root)
    {
        var containerPath = Path.Combine(root, "META-INF", "container.xml");
        if (File.Exists(containerPath))
        {
            var container = XDocument.Load(containerPath);
            var fullPath = container.Descendants().FirstOrDefault(element => element.Name.LocalName == "rootfile")?.Attribute("full-path")?.Value;
            var resolved = fullPath is null ? null : EpubPathSecurity.Resolve(fullPath, root, root);
            if (resolved is not null && File.Exists(resolved)) return resolved;
        }
        return Directory.EnumerateFiles(root, "*.opf", SearchOption.AllDirectories).FirstOrDefault()
            ?? throw new InvalidDataException("The EPUB package document could not be found.");
    }

    private static string? ImageReferencedByHtml(string htmlPath, string root)
    {
        if (!File.Exists(htmlPath)) return null;
        var html = File.ReadAllText(htmlPath);
        var match = Regex.Match(html, "<(?:img|image)\\b[^>]*(?:src|xlink:href|href)=[\\\"']([^\\\"']+)[\\\"']", RegexOptions.IgnoreCase);
        return match.Success ? EpubPathSecurity.Resolve(match.Groups[1].Value, Path.GetDirectoryName(htmlPath)!, root) : null;
    }

    private sealed record ManifestItem(string Href, string MediaType);
}
