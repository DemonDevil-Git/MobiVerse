using System.Runtime.InteropServices;
using System.Text;

namespace MobiVerse.App;

internal static class AppDiagnostics
{
    private static readonly object Gate = new();
    private static readonly string LogDirectory = AppPaths.DataFile("Logs");

    internal static string CurrentLogPath => Path.Combine(LogDirectory, $"mobiverse-{DateTime.Now:yyyyMMdd}.log");

    internal static void Write(string message, Exception? exception = null)
    {
        try
        {
            Directory.CreateDirectory(LogDirectory);
            var entry = new StringBuilder()
                .Append(DateTimeOffset.Now.ToString("O"))
                .Append("  ")
                .AppendLine(message);
            if (exception is not null) entry.AppendLine(exception.ToString());
            lock (Gate) File.AppendAllText(CurrentLogPath, entry.ToString());
        }
        catch { }
    }

    internal static void WriteStartup()
    {
        Write($"Application starting. Version={typeof(App).Assembly.GetName().Version}; " +
              $"OS={RuntimeInformation.OSDescription}; OSArchitecture={RuntimeInformation.OSArchitecture}; " +
              $"ProcessArchitecture={RuntimeInformation.ProcessArchitecture}; Runtime={RuntimeInformation.FrameworkDescription}");
    }
}
