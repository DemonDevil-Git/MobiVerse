using System.Windows;
using System.Windows.Threading;

namespace MobiVerse.App;

public partial class App : Application
{
    public static IReadOnlyList<string> StartupFiles { get; private set; } = [];

    protected override void OnStartup(StartupEventArgs e)
    {
        AppDiagnostics.WriteStartup();
        DispatcherUnhandledException += OnDispatcherUnhandledException;
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
            AppDiagnostics.Write("Unhandled AppDomain exception", args.ExceptionObject as Exception);
        TaskScheduler.UnobservedTaskException += (_, args) =>
        {
            AppDiagnostics.Write("Unobserved task exception", args.Exception);
            args.SetObserved();
        };
        StartupFiles = e.Args
            .Select(Path.GetFullPath)
            .Where(File.Exists)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        base.OnStartup(e);
    }

    private static void OnDispatcherUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        AppDiagnostics.Write("Unhandled UI exception", e.Exception);
        e.Handled = true;
        MessageBox.Show(
            $"MobiVerse recovered from an unexpected error.\n\n{e.Exception.Message}\n\nDiagnostic log:\n{AppDiagnostics.CurrentLogPath}",
            "MobiVerse error",
            MessageBoxButton.OK,
            MessageBoxImage.Error);
        if (Current.MainWindow is null || !Current.MainWindow.IsLoaded)
            Current.Shutdown(-1);
    }
}
