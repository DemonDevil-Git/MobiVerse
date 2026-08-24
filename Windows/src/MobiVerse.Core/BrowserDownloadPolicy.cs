namespace MobiVerse.Core;

public sealed record BrowserNavigationResponseInfo(
    Uri? Url,
    string? MimeType,
    string? SuggestedFileName,
    string? ContentDisposition,
    bool IsForMainFrame,
    bool CanShowMimeType);

public static class BrowserDownloadPolicy
{
    private static readonly HashSet<string> BookMimeTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "application/epub+zip", "application/x-mobipocket-ebook", "application/vnd.amazon.ebook",
        "application/zip", "application/x-rar-compressed", "application/vnd.rar"
    };

    private static readonly HashSet<string> BookExtensions = new(StringComparer.OrdinalIgnoreCase)
    { ".epub", ".mobi", ".azw", ".azw3", ".cbz", ".cbr", ".zip" };

    public static bool ShouldDownload(BrowserNavigationResponseInfo response, bool automaticallyDownloadsPdfs)
    {
        if (!response.CanShowMimeType) return true;
        if (!response.IsForMainFrame) return false;
        if (response.ContentDisposition?.Contains("attachment", StringComparison.OrdinalIgnoreCase) == true) return true;

        var mimeType = response.MimeType?.Split(';', 2)[0].Trim() ?? string.Empty;
        if (BookMimeTypes.Contains(mimeType)) return true;

        var extensions = CandidateExtensions(response);
        if (extensions.Any(BookExtensions.Contains)) return true;
        return automaticallyDownloadsPdfs &&
               (mimeType.Equals("application/pdf", StringComparison.OrdinalIgnoreCase) || extensions.Contains(".pdf"));
    }

    private static HashSet<string> CandidateExtensions(BrowserNavigationResponseInfo response)
    {
        var result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (response.Url is not null) Add(Path.GetExtension(response.Url.AbsolutePath));
        Add(Path.GetExtension(response.SuggestedFileName ?? string.Empty));
        return result;

        void Add(string extension)
        {
            if (!string.IsNullOrWhiteSpace(extension)) result.Add(extension);
        }
    }
}
