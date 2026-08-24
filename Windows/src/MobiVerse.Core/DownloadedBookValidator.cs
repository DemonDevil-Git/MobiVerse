using System.Text;

namespace MobiVerse.Core;

public sealed class DownloadedBookValidationException() : Exception(
    "The download is not a supported EPUB, MOBI, AZW, comic archive, or PDF file.");

public static class DownloadedBookValidator
{
    public static string ValidatedExtension(string path, string suggestedExtension)
    {
        using var stream = File.OpenRead(path);
        var header = new byte[Math.Min(4096, (int)Math.Min(stream.Length, 4096))];
        _ = stream.Read(header, 0, header.Length);
        var extension = suggestedExtension.TrimStart('.').ToLowerInvariant();
        var zip = StartsWith(header, [0x50, 0x4b]);
        var pdf = Encoding.ASCII.GetString(header.Take(5).ToArray()) == "%PDF-";
        var rar = Encoding.ASCII.GetString(header.Take(4).ToArray()) == "Rar!";
        var mobi = header.Length >= 68 && Encoding.ASCII.GetString(header, 60, 8).Contains("BOOKMOBI", StringComparison.Ordinal);
        var epub = zip && Encoding.ASCII.GetString(header).Contains("application/epub+zip", StringComparison.Ordinal);
        var prefix = Encoding.UTF8.GetString(header.Take(256).ToArray()).ToLowerInvariant();
        var looksLikeHtml = prefix.Contains("<!doctype html") || prefix.Contains("<html");
        var executable = StartsWith(header, [0xcf, 0xfa, 0xed, 0xfe]) ||
                         StartsWith(header, [0xce, 0xfa, 0xed, 0xfe]) || StartsWith(header, [0x4d, 0x5a]);
        if (looksLikeHtml || executable) throw new DownloadedBookValidationException();

        return extension switch
        {
            "epub" when epub => "epub",
            "cbz" when zip => "cbz",
            "zip" when zip => "zip",
            "pdf" when pdf => "pdf",
            "cbr" when rar => "cbr",
            "mobi" when mobi => "mobi",
            "azw" when mobi => "azw",
            "azw3" when mobi => "azw3",
            _ when epub => "epub",
            _ when pdf => "pdf",
            _ when rar => "cbr",
            _ when mobi => string.IsNullOrWhiteSpace(extension) ? "mobi" : extension,
            _ when zip => "zip",
            _ => throw new DownloadedBookValidationException()
        };
    }

    private static bool StartsWith(byte[] value, byte[] prefix) =>
        value.Length >= prefix.Length && value.AsSpan(0, prefix.Length).SequenceEqual(prefix);
}
