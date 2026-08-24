namespace MobiVerse.App;

internal static class PortableRuntime
{
    public static string? WebView2ExecutableFolder()
    {
        var directory = Path.Combine(AppContext.BaseDirectory, "ThirdParty", "WebView2");
        return File.Exists(Path.Combine(directory, "msedgewebview2.exe")) ? directory : null;
    }
}
