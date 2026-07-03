namespace MobiVerse.Core;

public sealed class ToolchainLocator(string applicationDirectory) : IToolchainLocator
{
    public ToolchainAvailability Inspect()
    {
        var bundled = Path.Combine(applicationDirectory, "ThirdParty", "calibre");
        var bundledDirectories = new[]
        {
            bundled,
            Path.Combine(bundled, "Calibre"),
            Path.Combine(bundled, "Calibre Portable", "Calibre")
        };
        var bundledConvert = Find("ebook-convert.exe", bundledDirectories);
        var bundledMeta = Find("ebook-meta.exe", bundledDirectories);
        var bundledCheck = Existing(Path.Combine(applicationDirectory, "ThirdParty", "epubcheck", "epubcheck.bat"));
        if (bundledConvert is not null && bundledMeta is not null)
            return new(bundledConvert, bundledMeta, bundledCheck ?? FindOnPath("epubcheck.bat"), true);

        var systemDirectories = new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Calibre2"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Calibre2")
        };
        var convert = Find("ebook-convert.exe", systemDirectories) ?? FindOnPath("ebook-convert.exe");
        var meta = Find("ebook-meta.exe", systemDirectories) ?? FindOnPath("ebook-meta.exe");
        return new(convert, meta, FindOnPath("epubcheck.bat") ?? FindOnPath("epubcheck.exe"), false);
    }

    private static string? Find(string name, IEnumerable<string> directories) =>
        directories.Select(directory => Path.Combine(directory, name)).FirstOrDefault(File.Exists);

    private static string? FindOnPath(string name) => Find(
        name,
        (Environment.GetEnvironmentVariable("PATH") ?? string.Empty).Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries));

    private static string? Existing(string path) => File.Exists(path) ? path : null;
}
