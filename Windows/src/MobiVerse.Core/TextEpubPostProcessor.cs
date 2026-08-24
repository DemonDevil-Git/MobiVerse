using System.IO.Compression;
using System.Text;
using System.Text.RegularExpressions;

namespace MobiVerse.Core;

public sealed record TextEpubPostProcessResult(
    int RepairedIdentifierCount,
    int RemovedBrokenResourceCount,
    int ReorderedNavigationCount)
{
    public string ReportText => $"""
Text EPUB post-processing
-------------------------
EPUB 3 semantic markup preserved: yes
Invalid identifiers repaired: {RepairedIdentifierCount}
Broken style/resource references removed: {RemovedBrokenResourceCount}
Navigation playOrder values repaired: {ReorderedNavigationCount}
""";
}

public sealed class TextEpubPostProcessor
{
    private static readonly HashSet<string> MarkupExtensions = new(StringComparer.OrdinalIgnoreCase)
    { ".xhtml", ".html", ".htm", ".xml", ".opf", ".ncx" };

    public TextEpubPostProcessResult Process(string epubPath)
    {
        var workspace = TemporaryDirectory();
        try
        {
            EpubPathSecurity.ExtractSafely(epubPath, workspace);
            var files = Directory.EnumerateFiles(workspace, "*", SearchOption.AllDirectories).ToArray();
            var identifiers = RepairInvalidIdentifiers(files);
            var resources = RemoveBrokenResourceReferences(files, workspace);
            var navigation = RepairNavigationOrder(files);
            var result = new TextEpubPostProcessResult(identifiers, resources, navigation);
            if (identifiers + resources + navigation > 0) Rebuild(workspace, epubPath);
            return result;
        }
        finally { try { Directory.Delete(workspace, true); } catch { } }
    }

    private static int RepairInvalidIdentifiers(IReadOnlyList<string> files)
    {
        var regex = new Regex("\\bid\\s*=\\s*([\\\"'])([^\\\"']+)\\1", RegexOptions.IgnoreCase);
        var mapping = new Dictionary<string, string>(StringComparer.Ordinal);
        var used = new HashSet<string>(StringComparer.Ordinal);
        foreach (var file in files.Where(file => MarkupExtensions.Contains(Path.GetExtension(file))))
        {
            foreach (Match match in regex.Matches(File.ReadAllText(file)))
            {
                var identifier = match.Groups[2].Value;
                used.Add(identifier);
                if (IsValidXmlIdentifier(identifier) || mapping.ContainsKey(identifier)) continue;
                var baseValue = SanitizeIdentifier(identifier);
                var replacement = baseValue;
                var suffix = 2;
                while (used.Contains(replacement)) replacement = $"{baseValue}-{suffix++}";
                mapping[identifier] = replacement;
                used.Add(replacement);
            }
        }

        if (mapping.Count == 0) return 0;
        foreach (var file in files.Where(file => MarkupExtensions.Contains(Path.GetExtension(file))))
        {
            var text = File.ReadAllText(file);
            var original = text;
            foreach (var pair in mapping)
            {
                var escaped = Regex.Escape(pair.Key);
                text = Regex.Replace(text, $"(\\bid\\s*=\\s*[\\\"']){escaped}([\\\"'])", $"$1{pair.Value}$2", RegexOptions.IgnoreCase);
                text = text.Replace($"#{pair.Key}", $"#{pair.Value}", StringComparison.Ordinal);
            }
            if (text != original) WriteText(file, text);
        }
        return mapping.Count;
    }

    private static int RemoveBrokenResourceReferences(IReadOnlyList<string> files, string root)
    {
        var removed = 0;
        foreach (var file in files.Where(file => Path.GetExtension(file).Equals(".css", StringComparison.OrdinalIgnoreCase)))
        {
            var css = File.ReadAllText(file);
            var original = css;
            foreach (Match match in Regex.Matches(css, @"@font-face\s*\{.*?\}", RegexOptions.IgnoreCase | RegexOptions.Singleline).Cast<Match>().Reverse())
            {
                if (!MissingUrlTokens(match.Value, file, root).Any()) continue;
                css = css.Remove(match.Index, match.Length);
                removed++;
            }

            foreach (var token in MissingUrlTokens(css, file, root))
            {
                var declaration = new Regex(@"(?im)^\s*[-a-z0-9_]+\s*:\s*[^;{}]*" + Regex.Escape(token) + @"[^;{}]*;\s*");
                var replaced = declaration.Replace(css, "");
                if (replaced != css) { css = replaced; removed++; }
            }
            if (css != original) WriteText(file, css);
        }

        foreach (var file in files.Where(file => new[] { ".xhtml", ".html", ".htm" }.Contains(Path.GetExtension(file), StringComparer.OrdinalIgnoreCase)))
        {
            var markup = File.ReadAllText(file);
            var original = markup;
            foreach (Match match in Regex.Matches(markup, @"<link\b[^>]*>", RegexOptions.IgnoreCase).Cast<Match>().Reverse())
            {
                if (!match.Value.Contains("stylesheet", StringComparison.OrdinalIgnoreCase)) continue;
                var href = Attribute("href", match.Value);
                if (href is null || !IsMissingLocalResource(href, file, root)) continue;
                markup = markup.Remove(match.Index, match.Length);
                removed++;
            }
            if (markup != original) WriteText(file, markup);
        }
        return removed;
    }

    private static int RepairNavigationOrder(IReadOnlyList<string> files)
    {
        var repaired = 0;
        var regex = new Regex("playOrder\\s*=\\s*([\\\"'])\\d+\\1", RegexOptions.IgnoreCase);
        foreach (var file in files.Where(file => Path.GetExtension(file).Equals(".ncx", StringComparison.OrdinalIgnoreCase)))
        {
            var index = 0;
            var text = File.ReadAllText(file);
            var replaced = regex.Replace(text, match =>
            {
                index++;
                var expected = $"playOrder={match.Groups[1].Value}{index}{match.Groups[1].Value}";
                if (match.Value != expected) repaired++;
                return expected;
            });
            if (replaced != text) WriteText(file, replaced);
        }
        return repaired;
    }

    private static IEnumerable<string> MissingUrlTokens(string text, string file, string root)
    {
        var regex = new Regex("url\\(\\s*([\\\"']?)([^\\\"')]+)\\1\\s*\\)", RegexOptions.IgnoreCase);
        return regex.Matches(text).Cast<Match>()
            .Where(match => IsMissingLocalResource(match.Groups[2].Value.Trim(), file, root))
            .Select(match => match.Value).ToArray();
    }

    private static bool IsMissingLocalResource(string rawValue, string file, string root)
    {
        if (rawValue.StartsWith("data:", StringComparison.OrdinalIgnoreCase) ||
            rawValue.StartsWith("http:", StringComparison.OrdinalIgnoreCase) ||
            rawValue.StartsWith("https:", StringComparison.OrdinalIgnoreCase) || rawValue.StartsWith('#')) return false;
        var value = rawValue.Split('#', 2)[0];
        try { value = Uri.UnescapeDataString(value); } catch { }
        var candidate = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(file)!, value.Replace('/', Path.DirectorySeparatorChar)));
        return !EpubPathSecurity.Contains(candidate, root) || !File.Exists(candidate);
    }

    private static string? Attribute(string name, string tag)
    {
        var match = Regex.Match(tag, $"\\b{Regex.Escape(name)}\\s*=\\s*([\\\"'])([^\\\"']+)\\1", RegexOptions.IgnoreCase);
        return match.Success ? match.Groups[2].Value : null;
    }

    private static bool IsValidXmlIdentifier(string value) =>
        value.Length > 0 && (value[0] == '_' || char.IsLetter(value[0])) && value.Skip(1).All(character => char.IsLetterOrDigit(character) || ".-_".Contains(character));

    private static string SanitizeIdentifier(string value)
    {
        var body = new string(value.Select(character => char.IsLetterOrDigit(character) || ".-_".Contains(character) ? character : '-').ToArray());
        return "mv-" + (body.Length == 0 ? "id" : body);
    }

    private static void Rebuild(string root, string epubPath)
    {
        var replacement = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(epubPath))!, $".mobiverse-text-repair-{Guid.NewGuid():N}.epub");
        try
        {
            using (var stream = new FileStream(replacement, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None))
            using (var archive = new ZipArchive(stream, ZipArchiveMode.Create))
            {
                var mimetype = Path.Combine(root, "mimetype");
                if (File.Exists(mimetype)) AddFile(archive, mimetype, "mimetype", CompressionLevel.NoCompression);
                foreach (var file in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories)
                             .Where(file => !file.Equals(mimetype, StringComparison.OrdinalIgnoreCase))
                             .OrderBy(file => Path.GetRelativePath(root, file), StringComparer.Ordinal))
                    AddFile(archive, file, Path.GetRelativePath(root, file).Replace('\\', '/'), CompressionLevel.Optimal);
            }
            File.Move(replacement, epubPath, true);
        }
        finally { try { File.Delete(replacement); } catch { } }
    }

    private static void AddFile(ZipArchive archive, string path, string name, CompressionLevel level)
    {
        var entry = archive.CreateEntry(name, level);
        entry.LastWriteTime = new DateTimeOffset(1980, 1, 1, 0, 0, 0, TimeSpan.Zero);
        using var input = File.OpenRead(path);
        using var output = entry.Open();
        input.CopyTo(output);
    }

    private static void WriteText(string path, string value) => File.WriteAllText(path, value, new UTF8Encoding(false));

    private static string TemporaryDirectory()
    {
        var path = Path.Combine(Path.GetTempPath(), "MobiVerseTextEpubRepair", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(path);
        return path;
    }
}
