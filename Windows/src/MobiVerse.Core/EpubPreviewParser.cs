using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace MobiVerse.Core;

public sealed class EpubPreviewParser
{
    private static readonly HashSet<string> ImageExtensions = new(StringComparer.OrdinalIgnoreCase)
    { ".jpg", ".jpeg", ".png", ".gif", ".webp" };

    public EpubPreviewBook Parse(string epubPath, string extractionDirectory)
    {
        Directory.CreateDirectory(extractionDirectory);
        EpubPathSecurity.ExtractSafely(epubPath, extractionDirectory);
        var opfPath = FindPackageDocument(extractionDirectory);
        var document = XDocument.Load(opfPath, LoadOptions.PreserveWhitespace);
        var packageDirectory = Path.GetDirectoryName(opfPath)!;
        var title = document.Descendants().FirstOrDefault(element => element.Name.LocalName == "title")?.Value.Trim();
        if (string.IsNullOrWhiteSpace(title)) title = Path.GetFileNameWithoutExtension(epubPath);

        var manifest = document.Descendants()
            .Where(element => element.Name.LocalName == "item")
            .Where(element => element.Attribute("id") is not null && element.Attribute("href") is not null)
            .GroupBy(element => element.Attribute("id")!.Value, StringComparer.Ordinal)
            .ToDictionary(
                group => group.Key,
                group =>
                {
                    var element = group.First();
                    return new ManifestItem(
                        element.Attribute("href")!.Value,
                        element.Attribute("media-type")?.Value ?? string.Empty,
                        element.Attribute("properties")?.Value ?? string.Empty);
                },
                StringComparer.Ordinal);
        var spineItems = document.Descendants()
            .Where(element => element.Name.LocalName == "itemref")
            .Select(element => element.Attribute("idref")?.Value)
            .Where(value => value is not null && manifest.ContainsKey(value))
            .Select(value => manifest[value!])
            .ToArray();
        var direction = document.Descendants().FirstOrDefault(element => element.Name.LocalName == "spine")?
            .Attribute("page-progression-direction")?.Value.Equals("rtl", StringComparison.OrdinalIgnoreCase) == true
            ? EpubReadingDirection.RightToLeft
            : EpubReadingDirection.LeftToRight;

        var pages = new List<EpubImagePreviewPage>();
        var imageOnlySpineCount = 0;
        foreach (var item in spineItems)
        {
            var itemPath = EpubPathSecurity.Resolve(item.Href, packageDirectory, extractionDirectory);
            if (itemPath is null || !File.Exists(itemPath)) continue;
            IReadOnlyList<string> imagePaths;
            if (item.MediaType.StartsWith("image/", StringComparison.OrdinalIgnoreCase))
            {
                imagePaths = [itemPath];
            }
            else if (item.MediaType.Contains("html", StringComparison.OrdinalIgnoreCase))
            {
                imagePaths = ImageReferencesFromImageOnlyXhtml(itemPath, extractionDirectory);
            }
            else continue;

            if (imagePaths.Count == 0) continue;
            imageOnlySpineCount++;
            foreach (var imagePath in imagePaths.Where(File.Exists).Where(path => ImageExtensions.Contains(Path.GetExtension(path))))
            {
                var dimensions = ReadDimensions(imagePath);
                var number = pages.Count + 1;
                pages.Add(new($"page-{number:00000}", $"Page {number}", imagePath, dimensions.Width, dimensions.Height));
            }
        }

        if (pages.Count >= 2 && imageOnlySpineCount * 5 >= Math.Max(1, spineItems.Length * 4))
            return new(title, epubPath, extractionDirectory, packageDirectory, direction, EpubPreviewKind.ImagePages, pages, []);

        var spinePaths = spineItems
            .Where(item => item.MediaType.Contains("html", StringComparison.OrdinalIgnoreCase))
            .Select(item => EpubPathSecurity.Resolve(item.Href, packageDirectory, extractionDirectory))
            .Where(path => path is not null && File.Exists(path))
            .Cast<string>()
            .ToArray();
        if (spinePaths.Length == 0) throw new InvalidDataException("No readable pages were found in this EPUB.");
        return new(title, epubPath, extractionDirectory, packageDirectory, direction, EpubPreviewKind.Web, [], spinePaths);
    }

    public string? ExtractCover(string epubPath, string extractionDirectory)
    {
        Directory.CreateDirectory(extractionDirectory);
        EpubPathSecurity.ExtractSafely(epubPath, extractionDirectory);
        var opfPath = FindPackageDocument(extractionDirectory);
        var document = XDocument.Load(opfPath);
        var packageDirectory = Path.GetDirectoryName(opfPath)!;
        var items = document.Descendants().Where(element => element.Name.LocalName == "item").ToArray();
        var coverId = document.Descendants().FirstOrDefault(element =>
            element.Name.LocalName == "meta" && element.Attribute("name")?.Value == "cover")?.Attribute("content")?.Value;
        var item = items.FirstOrDefault(element => HasProperty(element, "cover-image"))
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
        return new[] { Path.Combine(root, "content.opf"), Path.Combine(root, "OEBPS", "content.opf") }
                   .FirstOrDefault(File.Exists)
               ?? Directory.EnumerateFiles(root, "*.opf", SearchOption.AllDirectories).FirstOrDefault()
               ?? throw new InvalidDataException("The EPUB package document could not be found.");
    }

    private static IReadOnlyList<string> ImageReferencesFromImageOnlyXhtml(string htmlPath, string root)
    {
        try
        {
            var document = XDocument.Load(htmlPath, LoadOptions.PreserveWhitespace);
            var visibleText = string.Concat(document.DescendantNodes().OfType<XText>()
                .Where(node => !node.Ancestors().Any(ancestor =>
                    new[] { "head", "script", "style" }.Contains(ancestor.Name.LocalName, StringComparer.OrdinalIgnoreCase)))
                .Select(node => node.Value)).Trim();
            if (visibleText.Length > 0) return [];
            return document.Descendants()
                .Where(element => element.Name.LocalName.Equals("img", StringComparison.OrdinalIgnoreCase) ||
                                  element.Name.LocalName.Equals("image", StringComparison.OrdinalIgnoreCase))
                .Select(element => element.Attributes().FirstOrDefault(attribute =>
                    attribute.Name.LocalName.Equals("src", StringComparison.OrdinalIgnoreCase) ||
                    attribute.Name.LocalName.Equals("href", StringComparison.OrdinalIgnoreCase))?.Value)
                .Where(value => !string.IsNullOrWhiteSpace(value) && !value.StartsWith("data:", StringComparison.OrdinalIgnoreCase))
                .Select(value => EpubPathSecurity.Resolve(value!, Path.GetDirectoryName(htmlPath)!, root))
                .Where(path => path is not null)
                .Cast<string>()
                .ToArray();
        }
        catch { return []; }
    }

    private static (int Width, int Height) ReadDimensions(string path)
    {
        try { return ImageDimensions.Read(path); }
        catch { return (1200, 1800); }
    }

    private static bool HasProperty(XElement element, string value) =>
        element.Attribute("properties")?.Value.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
            .Contains(value, StringComparer.OrdinalIgnoreCase) == true;

    private sealed record ManifestItem(string Href, string MediaType, string Properties);
}
