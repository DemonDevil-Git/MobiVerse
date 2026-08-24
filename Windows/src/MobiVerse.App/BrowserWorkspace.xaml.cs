using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using Microsoft.Win32;
using MobiVerse.Core;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Net;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace MobiVerse.App;

public partial class BrowserWorkspace : UserControl, INotifyPropertyChanged
{
    private const string HomeUrl = "https://www.google.com/search?q=ebooks";
    private readonly BrowserPreferencesStore _store = new(AppPaths.DataFile("browser-preferences.json"));
    private readonly HashSet<string> _capturedResponses = new(StringComparer.OrdinalIgnoreCase);
    private BrowserPreferences _preferences;
    private CoreWebView2Environment? _environment;
    private bool _initialized;

    public BrowserWorkspace()
    {
        InitializeComponent();
        _preferences = _store.Load();
        foreach (var bookmark in _preferences.Bookmarks) Bookmarks.Add(bookmark);
        DataContext = this;
        Loaded += BrowserWorkspace_Loaded;
    }

    public ObservableCollection<BrowserBookmark> Bookmarks { get; } = [];
    public ObservableCollection<DownloadItemViewModel> Downloads { get; } = [];
    public bool AutomaticallyDownloadsPdfs
    {
        get => _preferences.AutomaticallyDownloadsPdfs;
        set { _preferences.AutomaticallyDownloadsPdfs = value; OnPropertyChanged(); SavePreferences(); }
    }
    public event EventHandler<string>? BookDownloaded;
    public event PropertyChangedEventHandler? PropertyChanged;

    private async void BrowserWorkspace_Loaded(object sender, RoutedEventArgs e)
    {
        if (_initialized) return;
        _initialized = true;
        var userData = AppPaths.DataFile("BrowserData");
        _environment = await CoreWebView2Environment.CreateAsync(PortableRuntime.WebView2ExecutableFolder(), userData);
        await AddTabAsync(HomeUrl);
    }

    private BrowserTab? ActiveTab => (Tabs.SelectedItem as TabItem)?.Tag as BrowserTab;

    private async Task AddTabAsync(string url)
    {
        if (_environment is null) return;
        var browser = new WebView2 { CreationProperties = new CoreWebView2CreationProperties { UserDataFolder = _environment.UserDataFolder } };
        var title = new TextBlock { Text = "New tab", MaxWidth = 170, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
        var close = new Button { Content = "×", Padding = new Thickness(7, 0, 7, 0), Margin = new Thickness(6, 0, 0, 0), Tag = browser };
        close.Click += CloseTab_Click;
        var header = new StackPanel { Orientation = Orientation.Horizontal };
        header.Children.Add(title); header.Children.Add(close);
        var item = new TabItem { Header = header, Content = browser };
        var tab = new BrowserTab(browser, item, title);
        item.Tag = tab;
        Tabs.Items.Add(item);
        Tabs.SelectedItem = item;
        await browser.EnsureCoreWebView2Async(_environment);
        Configure(tab);
        browser.CoreWebView2.Navigate(NormalizeUrl(url));
    }

    private void Configure(BrowserTab tab)
    {
        var core = tab.Browser.CoreWebView2;
        core.Settings.AreDefaultContextMenusEnabled = true;
        core.Settings.AreDevToolsEnabled = true;
        core.Settings.IsStatusBarEnabled = false;
        core.DocumentTitleChanged += (_, _) => Dispatcher.Invoke(() =>
        {
            tab.Title.Text = string.IsNullOrWhiteSpace(core.DocumentTitle) ? "New tab" : core.DocumentTitle;
            if (ActiveTab == tab) StatusText.Text = core.DocumentTitle;
        });
        core.SourceChanged += (_, _) => Dispatcher.Invoke(() => { if (ActiveTab == tab) AddressBox.Text = core.Source; });
        core.NavigationStarting += (_, _) => Dispatcher.Invoke(() => StatusText.Text = "Loading…");
        core.NavigationCompleted += (_, args) => Dispatcher.Invoke(() => StatusText.Text = args.IsSuccess ? "Ready" : $"Could not load page ({args.WebErrorStatus})");
        core.NewWindowRequested += async (_, args) =>
        {
            args.Handled = true;
            await Dispatcher.InvokeAsync(async () => await AddTabAsync(args.Uri));
        };
        core.DownloadStarting += (_, args) => Dispatcher.Invoke(() => BeginDownload(args));
        core.WebResourceResponseReceived += (_, args) => CapturePdfResponseAsync(tab, args);
    }

    private async void CapturePdfResponseAsync(BrowserTab tab, CoreWebView2WebResourceResponseReceivedEventArgs args)
    {
        try
        {
            if (!AutomaticallyDownloadsPdfs || ActiveTab != tab) return;
            var requestUrl = args.Request.Uri;
            if (!string.Equals(NormalizeComparable(requestUrl), NormalizeComparable(tab.Browser.Source?.AbsoluteUri), StringComparison.OrdinalIgnoreCase)) return;
            var mime = Header(args.Response.Headers, "Content-Type").Split(';', 2)[0].Trim();
            var suggested = SuggestedFileName(Header(args.Response.Headers, "Content-Disposition"), requestUrl);
            var response = new BrowserNavigationResponseInfo(new Uri(requestUrl), mime, suggested,
                Header(args.Response.Headers, "Content-Disposition"), true, true);
            if (!BrowserDownloadPolicy.ShouldDownload(response, true) || !mime.Equals("application/pdf", StringComparison.OrdinalIgnoreCase)) return;
            if (!_capturedResponses.Add(requestUrl)) return;
            await using var content = await args.Response.GetContentAsync();
            var destination = AvailableDestination(Path.ChangeExtension(suggested, ".pdf"));
            await using (var output = File.Create(destination)) await content.CopyToAsync(output);
            await CompleteValidatedDownloadAsync(destination);
        }
        catch (Exception exception) { Dispatcher.Invoke(() => StatusText.Text = $"PDF download failed: {exception.Message}"); }
    }

    private void BeginDownload(CoreWebView2DownloadStartingEventArgs args)
    {
        args.Handled = true;
        var fileName = Path.GetFileName(args.ResultFilePath);
        args.ResultFilePath = AvailableDestination(fileName);
        var item = new DownloadItemViewModel(args.DownloadOperation, args.ResultFilePath);
        Downloads.Insert(0, item);
        args.DownloadOperation.BytesReceivedChanged += (_, _) => Dispatcher.Invoke(item.Refresh);
        args.DownloadOperation.StateChanged += async (_, _) =>
        {
            await Dispatcher.InvokeAsync(item.Refresh);
            if (args.DownloadOperation.State == CoreWebView2DownloadState.Completed)
                await CompleteValidatedDownloadAsync(item.LocalPath, item);
        };
        LibraryColumn.Width = new GridLength(340);
    }

    private async Task CompleteValidatedDownloadAsync(string path, DownloadItemViewModel? item = null)
    {
        try
        {
            var extension = DownloadedBookValidator.ValidatedExtension(path, Path.GetExtension(path));
            var validatedPath = Path.ChangeExtension(path, extension);
            if (!validatedPath.Equals(path, StringComparison.OrdinalIgnoreCase))
            {
                validatedPath = AvailableDestination(Path.GetFileName(validatedPath));
                File.Move(path, validatedPath);
            }
            if (item is not null) item.SetLocalPath(validatedPath);
            await Dispatcher.InvokeAsync(() =>
            {
                StatusText.Text = $"Downloaded {Path.GetFileName(validatedPath)}";
                BookDownloaded?.Invoke(this, validatedPath);
            });
        }
        catch (Exception exception)
        {
            await Dispatcher.InvokeAsync(() =>
            {
                item?.Fail(exception.Message);
                StatusText.Text = exception.Message;
            });
        }
    }

    private string AvailableDestination(string fileName)
    {
        var directory = DownloadDirectory();
        Directory.CreateDirectory(directory);
        fileName = SanitizeFileName(fileName);
        var candidate = Path.Combine(directory, fileName);
        var index = 2;
        while (File.Exists(candidate)) candidate = Path.Combine(directory, $"{Path.GetFileNameWithoutExtension(fileName)} {index++}{Path.GetExtension(fileName)}");
        return candidate;
    }

    private string DownloadDirectory()
    {
        var directory = _preferences.DownloadDirectory;
        return string.IsNullOrWhiteSpace(directory) || !Directory.Exists(directory)
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "MobiVerse")
            : directory;
    }

    private static string SanitizeFileName(string value)
    {
        var fileName = string.IsNullOrWhiteSpace(value) ? "download" : Path.GetFileName(value);
        foreach (var character in Path.GetInvalidFileNameChars()) fileName = fileName.Replace(character, '-');
        return string.IsNullOrWhiteSpace(fileName) ? "download" : fileName;
    }

    private static string SuggestedFileName(string disposition, string url)
    {
        var match = Regex.Match(disposition, """filename\*?=(?:UTF-8''|["']?)([^"';]+)""", RegexOptions.IgnoreCase);
        if (match.Success) return WebUtility.UrlDecode(match.Groups[1].Value.Trim());
        var value = Path.GetFileName(new Uri(url).AbsolutePath);
        return string.IsNullOrWhiteSpace(value) ? "download.pdf" : WebUtility.UrlDecode(value);
    }

    private static string Header(CoreWebView2HttpResponseHeaders headers, string name)
    {
        try { return headers.GetHeader(name); } catch { return string.Empty; }
    }

    private static string NormalizeComparable(string? value) => value?.TrimEnd('/') ?? string.Empty;
    private static string NormalizeUrl(string value)
    {
        value = value.Trim();
        if (Uri.TryCreate(value, UriKind.Absolute, out var uri) && uri.Scheme is "http" or "https" or "file") return uri.AbsoluteUri;
        if (value.Contains('.') && !value.Contains(' ')) return "https://" + value;
        return "https://www.google.com/search?q=" + Uri.EscapeDataString(value);
    }

    private async void NewTab_Click(object sender, RoutedEventArgs e) => await AddTabAsync(HomeUrl);
    private void CloseTab_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not WebView2 browser) return;
        var item = Tabs.Items.Cast<TabItem>().FirstOrDefault(tab => ReferenceEquals(((BrowserTab)tab.Tag).Browser, browser));
        if (item is null) return;
        browser.Dispose(); Tabs.Items.Remove(item);
        if (Tabs.Items.Count == 0) _ = AddTabAsync(HomeUrl);
        e.Handled = true;
    }
    private void Go_Click(object sender, RoutedEventArgs e) => Navigate(AddressBox.Text);
    private void AddressBox_KeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Enter) { Navigate(AddressBox.Text); e.Handled = true; } }
    private void Navigate(string value) { if (ActiveTab?.Browser.CoreWebView2 is { } core) core.Navigate(NormalizeUrl(value)); }
    private void Home_Click(object sender, RoutedEventArgs e) => Navigate(HomeUrl);
    private void Back_Click(object sender, RoutedEventArgs e) { if (ActiveTab?.Browser.CanGoBack == true) ActiveTab.Browser.GoBack(); }
    private void Forward_Click(object sender, RoutedEventArgs e) { if (ActiveTab?.Browser.CanGoForward == true) ActiveTab.Browser.GoForward(); }
    private void Reload_Click(object sender, RoutedEventArgs e) => ActiveTab?.Browser.Reload();
    private void Tabs_SelectionChanged(object sender, SelectionChangedEventArgs e) { if (ActiveTab?.Browser.Source is { } source) AddressBox.Text = source.AbsoluteUri; }
    private void Library_Click(object sender, RoutedEventArgs e) => LibraryColumn.Width = LibraryColumn.Width.Value == 0 ? new GridLength(340) : new GridLength(0);
    private void CloseLibrary_Click(object sender, RoutedEventArgs e) => LibraryColumn.Width = new GridLength(0);

    private void Bookmark_Click(object sender, RoutedEventArgs e)
    {
        var core = ActiveTab?.Browser.CoreWebView2;
        if (core is null || string.IsNullOrWhiteSpace(core.Source)) return;
        var existing = Bookmarks.FirstOrDefault(value => NormalizeComparable(value.Url) == NormalizeComparable(core.Source));
        if (existing is not null) Bookmarks.Remove(existing);
        else Bookmarks.Insert(0, new(string.IsNullOrWhiteSpace(core.DocumentTitle) ? new Uri(core.Source).Host : core.DocumentTitle, core.Source));
        SavePreferences();
    }
    private void RemoveBookmark_Click(object sender, RoutedEventArgs e) { if ((sender as Button)?.Tag is BrowserBookmark bookmark) { Bookmarks.Remove(bookmark); SavePreferences(); } }
    private void BookmarksList_MouseDoubleClick(object sender, MouseButtonEventArgs e) { if (BookmarksList.SelectedItem is BrowserBookmark bookmark) Navigate(bookmark.Url); }
    private void AutoPdfCheck_Click(object sender, RoutedEventArgs e) => AutomaticallyDownloadsPdfs = AutoPdfCheck.IsChecked == true;
    private void ChooseDownloadFolder_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "Choose browser download folder", Multiselect = false };
        if (dialog.ShowDialog(Window.GetWindow(this)) != true) return;
        _preferences.DownloadDirectory = dialog.FolderName; SavePreferences();
    }
    private void OpenDownloads_Click(object sender, RoutedEventArgs e)
    {
        var directory = DownloadDirectory();
        Directory.CreateDirectory(directory);
        Process.Start(new ProcessStartInfo(directory) { UseShellExecute = true });
    }
    private async void ClearBrowsingData_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show(Window.GetWindow(this), "Clear cookies, cache, permissions, and browsing history?", "Clear browsing data", MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return;
        foreach (var core in Tabs.Items.Cast<TabItem>().Select(item => ((BrowserTab)item.Tag).Browser.CoreWebView2).Where(value => value is not null))
            await core.Profile.ClearBrowsingDataAsync(CoreWebView2BrowsingDataKinds.AllProfile);
        StatusText.Text = "Browsing data cleared";
    }
    private void PauseDownload_Click(object sender, RoutedEventArgs e) => ((sender as Button)?.Tag as DownloadItemViewModel)?.Pause();
    private void ResumeDownload_Click(object sender, RoutedEventArgs e) => ((sender as Button)?.Tag as DownloadItemViewModel)?.Resume();
    private void CancelDownload_Click(object sender, RoutedEventArgs e) => ((sender as Button)?.Tag as DownloadItemViewModel)?.Cancel();
    private void RevealDownload_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is DownloadItemViewModel item && File.Exists(item.LocalPath))
            Process.Start(new ProcessStartInfo("explorer.exe") { ArgumentList = { "/select,", item.LocalPath }, UseShellExecute = true });
    }

    private void SavePreferences()
    {
        _preferences.Bookmarks = Bookmarks.ToList();
        _store.Save(_preferences);
    }
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
    private sealed record BrowserTab(WebView2 Browser, TabItem Item, TextBlock Title);
}

public sealed record BrowserBookmark(string Title, string Url);

public sealed class BrowserPreferences
{
    public bool AutomaticallyDownloadsPdfs { get; set; } = true;
    public string? DownloadDirectory { get; set; }
    public List<BrowserBookmark> Bookmarks { get; set; } = [];
}

public sealed class BrowserPreferencesStore
{
    private readonly string _path;
    public BrowserPreferencesStore(string? path = null) => _path = path ?? AppPaths.DataFile("browser-preferences.json");
    public BrowserPreferences Load() { try { return File.Exists(_path) ? JsonSerializer.Deserialize<BrowserPreferences>(File.ReadAllText(_path)) ?? new() : new(); } catch { return new(); } }
    public void Save(BrowserPreferences value) { try { Directory.CreateDirectory(Path.GetDirectoryName(_path)!); File.WriteAllText(_path, JsonSerializer.Serialize(value, new JsonSerializerOptions { WriteIndented = true })); } catch { } }
}

public sealed class DownloadItemViewModel(CoreWebView2DownloadOperation operation, string localPath) : INotifyPropertyChanged
{
    private string? _error;
    private bool _paused;
    public CoreWebView2DownloadOperation Operation { get; } = operation;
    public string LocalPath { get; private set; } = localPath;
    public string FileName => Path.GetFileName(LocalPath);
    public double ProgressPercent => (Operation.TotalBytesToReceive ?? 0) > 0 ? (double)Operation.BytesReceived / Operation.TotalBytesToReceive!.Value * 100 : 0;
    public string Detail => _error ?? Operation.State switch { CoreWebView2DownloadState.Completed => "Completed", _ when _paused => "Paused", CoreWebView2DownloadState.Interrupted => $"Interrupted: {Operation.InterruptReason}", _ => $"{ProgressPercent:0}%" };
    public bool CanPause => Operation.State == CoreWebView2DownloadState.InProgress && !_paused;
    public bool CanResume => Operation.CanResume;
    public bool CanCancel => Operation.State == CoreWebView2DownloadState.InProgress;
    public bool CanReveal => Operation.State == CoreWebView2DownloadState.Completed && File.Exists(LocalPath);
    public event PropertyChangedEventHandler? PropertyChanged;
    public void Pause() { _paused = true; Operation.Pause(); Refresh(); }
    public void Resume() { _paused = false; Operation.Resume(); Refresh(); }
    public void Cancel() { _paused = false; Operation.Cancel(); Refresh(); }
    public void SetLocalPath(string value) { LocalPath = value; Refresh(); }
    public void Fail(string message) { _error = message; Refresh(); }
    public void Refresh() { foreach (var name in new[] { nameof(LocalPath), nameof(FileName), nameof(ProgressPercent), nameof(Detail), nameof(CanPause), nameof(CanResume), nameof(CanCancel), nameof(CanReveal) }) PropertyChanged?.Invoke(this, new(name)); }
}
