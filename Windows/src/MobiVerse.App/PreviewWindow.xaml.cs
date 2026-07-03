using Microsoft.Web.WebView2.Core;
using MobiVerse.Core;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Imaging;

namespace MobiVerse.App;

public partial class PreviewWindow : Window
{
    private readonly EpubPreviewBook _book;
    private readonly ReadingPositionStore _positions = new();
    private int _pageIndex;
    private double _zoom = 1;
    private WindowState _previousWindowState;
    private WindowStyle _previousWindowStyle;
    private string? _webUserDataDirectory;
    private CoreWebView2Environment? _webEnvironment;

    public PreviewWindow(EpubPreviewBook book)
    {
        InitializeComponent();
        _book = book;
        Title = book.Title;
        TitleLabel.Text = book.Title;
        Closed += Window_Closed;
        if (book.Kind == EpubPreviewKind.ImagePages)
        {
            ModeLabel.Text = $"{book.ImagePages.Count} image pages";
            _pageIndex = Math.Clamp(_positions.Get(book.EpubPath), 0, book.ImagePages.Count - 1);
            PageSlider.Minimum = 0;
            PageSlider.Maximum = Math.Max(0, book.ImagePages.Count - 1);
            PageSlider.Value = _pageIndex;
            ShowPage();
        }
        else
        {
            ModeLabel.Text = "Text EPUB preview";
            ImageScroller.Visibility = Visibility.Collapsed;
            ImageControls.Visibility = Visibility.Collapsed;
            WebPreview.Visibility = Visibility.Visible;
            Loaded += async (_, _) => await InitializeWebPreviewAsync();
        }
    }

    private void ShowPage()
    {
        if (_book.ImagePages.Count == 0) return;
        _pageIndex = Math.Clamp(_pageIndex, 0, _book.ImagePages.Count - 1);
        var bitmap = new BitmapImage();
        bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad; bitmap.UriSource = new Uri(_book.ImagePages[_pageIndex].ImagePath); bitmap.EndInit(); bitmap.Freeze();
        PageImage.Source = bitmap;
        PageSlider.Value = _pageIndex;
        PageLabel.Text = $"{_pageIndex + 1} / {_book.ImagePages.Count}";
        PreviousButton.IsEnabled = _pageIndex > 0;
        NextButton.IsEnabled = _pageIndex < _book.ImagePages.Count - 1;
        _positions.Save(_book.EpubPath, _pageIndex);
    }

    private async Task InitializeWebPreviewAsync()
    {
        _webUserDataDirectory = Path.Combine(Path.GetTempPath(), "MobiVerseWebView", Guid.NewGuid().ToString("N"));
        var fixedRuntime = Path.Combine(AppContext.BaseDirectory, "ThirdParty", "WebView2");
        _webEnvironment = await CoreWebView2Environment.CreateAsync(Directory.Exists(fixedRuntime) ? fixedRuntime : null, _webUserDataDirectory);
        await WebPreview.EnsureCoreWebView2Async(_webEnvironment);
        var settings = WebPreview.CoreWebView2.Settings;
        settings.IsScriptEnabled = false;
        settings.AreDefaultScriptDialogsEnabled = false;
        settings.AreDevToolsEnabled = false;
        settings.AreDefaultContextMenusEnabled = false;
        WebPreview.CoreWebView2.AddWebResourceRequestedFilter("http://*", CoreWebView2WebResourceContext.All);
        WebPreview.CoreWebView2.AddWebResourceRequestedFilter("https://*", CoreWebView2WebResourceContext.All);
        WebPreview.CoreWebView2.WebResourceRequested += (_, args) =>
            args.Response = _webEnvironment.CreateWebResourceResponse(Stream.Null, 403, "Blocked", "Content-Type: text/plain");
        WebPreview.CoreWebView2.NavigationStarting += (_, args) =>
        {
            if (!Uri.TryCreate(args.Uri, UriKind.Absolute, out var uri) || !uri.IsFile || !EpubPathSecurity.Contains(uri.LocalPath, _book.ExtractionDirectory)) args.Cancel = true;
        };
        WebPreview.Source = new Uri(_book.StartDocumentPath!);
    }

    private void Move(int delta) { if (_book.Kind == EpubPreviewKind.ImagePages) { _pageIndex = Math.Clamp(_pageIndex + delta, 0, _book.ImagePages.Count - 1); ShowPage(); } }
    private void Previous_Click(object sender, RoutedEventArgs e) => Move(-1);
    private void Next_Click(object sender, RoutedEventArgs e) => Move(1);
    private void PageSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e) { if (IsLoaded && _book.Kind == EpubPreviewKind.ImagePages) { _pageIndex = (int)Math.Round(e.NewValue); ShowPage(); } }
    private void Zoom(double amount) { _zoom = Math.Clamp(_zoom + amount, .5, 3); ImageScale.ScaleX = _zoom; ImageScale.ScaleY = _zoom; }
    private void ZoomOut_Click(object sender, RoutedEventArgs e) => Zoom(-.1);
    private void ZoomIn_Click(object sender, RoutedEventArgs e) => Zoom(.1);
    private void Fit_Click(object sender, RoutedEventArgs e) { _zoom = 1; ImageScale.ScaleX = 1; ImageScale.ScaleY = 1; }
    private void Close_Click(object sender, RoutedEventArgs e) => Close();

    private void FullScreen_Click(object sender, RoutedEventArgs e)
    {
        if (WindowStyle != WindowStyle.None)
        {
            _previousWindowState = WindowState; _previousWindowStyle = WindowStyle;
            WindowStyle = WindowStyle.None; WindowState = WindowState.Maximized; FullScreenButton.ToolTip = "Exit full screen";
        }
        else
        {
            WindowStyle = _previousWindowStyle; WindowState = _previousWindowState; FullScreenButton.ToolTip = "Enter full screen";
        }
    }

    private void Window_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Left) { Move(-1); e.Handled = true; }
        else if (e.Key == Key.Right) { Move(1); e.Handled = true; }
        else if (e.Key == Key.Escape && WindowStyle == WindowStyle.None) { FullScreen_Click(sender, e); e.Handled = true; }
    }

    private void Window_PreviewMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (_book.Kind != EpubPreviewKind.ImagePages) return;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) Zoom(e.Delta > 0 ? .1 : -.1);
        else Move(e.Delta > 0 ? -1 : 1);
        e.Handled = true;
    }

    private void Window_Closed(object? sender, EventArgs e)
    {
        WebPreview.Dispose();
        try { Directory.Delete(_book.ExtractionDirectory, true); } catch { }
        if (_webUserDataDirectory is not null) try { Directory.Delete(_webUserDataDirectory, true); } catch { }
    }
}
