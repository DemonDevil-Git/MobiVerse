using System.IO.Compression;

namespace MobiVerse.Core;

public static class EpubPathSecurity
{
    public static string? Resolve(string reference, string relativeDirectory, string rootDirectory)
    {
        if (string.IsNullOrWhiteSpace(reference) || Uri.TryCreate(reference, UriKind.Absolute, out _)) return null;
        var clean = Uri.UnescapeDataString(reference.Split('#', '?')[0]).Replace('/', Path.DirectorySeparatorChar);
        if (Path.IsPathRooted(clean)) return null;
        var candidate = Path.GetFullPath(Path.Combine(relativeDirectory, clean));
        return Contains(candidate, rootDirectory) ? candidate : null;
    }

    public static bool Contains(string candidate, string root)
    {
        var rootPath = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var candidatePath = Path.GetFullPath(candidate);
        return candidatePath.StartsWith(rootPath, StringComparison.OrdinalIgnoreCase) ||
               string.Equals(candidatePath, rootPath.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase);
    }

    public static void ExtractSafely(string archivePath, string destinationDirectory)
    {
        Directory.CreateDirectory(destinationDirectory);
        using var archive = ZipFile.OpenRead(archivePath);
        foreach (var entry in archive.Entries)
        {
            var unixType = (entry.ExternalAttributes >> 16) & 0xF000;
            if (unixType == 0xA000) throw new InvalidDataException("EPUB contains a symbolic link.");
            var normalizedName = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
            if (string.IsNullOrEmpty(normalizedName)) continue;
            var outputPath = Path.GetFullPath(Path.Combine(destinationDirectory, normalizedName));
            if (!Contains(outputPath, destinationDirectory)) throw new InvalidDataException("EPUB entry escapes its extraction root.");
            if (entry.FullName.EndsWith('/'))
            {
                Directory.CreateDirectory(outputPath);
                continue;
            }
            Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
            using var source = entry.Open();
            using var destination = new FileStream(outputPath, FileMode.CreateNew, FileAccess.Write, FileShare.None);
            source.CopyTo(destination);
        }
    }
}
