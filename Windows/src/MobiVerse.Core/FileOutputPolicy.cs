namespace MobiVerse.Core;

public sealed class FileOutputPolicy
{
    public string EpubOutputPath(string inputPath)
    {
        var extension = Path.GetExtension(inputPath);
        if (!SupportedFormats.Convertable.Contains(extension))
            throw new ArgumentException($"Unsupported input extension: {extension}", nameof(inputPath));
        return AvailablePath(Path.GetDirectoryName(Path.GetFullPath(inputPath))!, Path.GetFileNameWithoutExtension(inputPath), ".epub");
    }

    public string ReportPath(string outputPath) => AvailablePath(
        Path.GetDirectoryName(Path.GetFullPath(outputPath))!,
        Path.GetFileNameWithoutExtension(outputPath),
        ".conversion-report.txt");

    private static string AvailablePath(string directory, string baseName, string extension)
    {
        var candidate = Path.Combine(directory, baseName + extension);
        if (!File.Exists(candidate)) return candidate;
        for (var index = 2; ; index++)
        {
            candidate = Path.Combine(directory, $"{baseName} {index}{extension}");
            if (!File.Exists(candidate)) return candidate;
        }
    }
}
