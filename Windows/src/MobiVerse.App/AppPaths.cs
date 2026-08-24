namespace MobiVerse.App;

internal static class AppPaths
{
    public static string DataDirectory { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "MobiVerse",
        "Portable");

    public static string DataFile(string relativePath) => Path.Combine(DataDirectory, relativePath);
}
