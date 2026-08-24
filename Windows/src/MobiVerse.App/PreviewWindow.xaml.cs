using Microsoft.Web.WebView2.Core;
using MobiVerse.Core;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace MobiVerse.App;

public partial class PreviewWindow : Window
{
    private readonly EpubPreviewBook _book;
    private readonly ReadingPositionStore _positions = new(AppPaths.DataFile("preview-reading-positions.json"));
    private readonly ReaderPreferencesStore _readerStore = new(AppPaths.DataFile("reader-preferences.json"));
    private ReaderPreferences _readerPreferences;
    private int _pageIndex;
    private int _sectionIndex;
    private int _textPageIndex;
    private int _textPageCount = 1;
    private bool _openLastPage;
    private bool _readerReady;
    private double _zoom = 1;
    private WindowState _previousWindowState;
    private WindowStyle _previousWindowStyle;
    private string? _webUserDataDirectory;
    private CoreWebView2Environment? _webEnvironment;

    public PreviewWindow(EpubPreviewBook book)
    {
        InitializeComponent();
        _book = book;
        _readerPreferences = _readerStore.Load();
        FontScaleSlider.Value = _readerPreferences.FontScale;
        LineHeightSlider.Value = _readerPreferences.LineHeight;
        Title = book.Title;
        TitleLabel.Text = book.Title;
        Closed += Window_Closed;
        if (book.Kind == EpubPreviewKind.ImagePages)
        {
            ModeLabel.Text = $"{book.ImagePages.Count} image pages";
            _pageIndex = Math.Clamp(_positions.GetPosition(book.EpubPath, false).PageIndex, 0, book.ImagePages.Count - 1);
            PageSlider.Minimum = 0;
            PageSlider.Maximum = Math.Max(0, book.ImagePages.Count - 1);
            PageSlider.Value = _pageIndex;
            ShowPage();
        }
        else
        {
            ModeLabel.Text = $"Text EPUB preview · {book.SpineDocumentPaths.Count} sections";
            ImageScroller.Visibility = Visibility.Collapsed;
            ImageControls.Visibility = Visibility.Collapsed;
            TextPageBorder.Visibility = Visibility.Visible;
            ReaderPositionBadge.Visibility = Visibility.Visible;
            TextControls.Visibility = Visibility.Visible;
            var position = _positions.GetPosition(book.EpubPath, true);
            _sectionIndex = Math.Clamp(position.SectionIndex, 0, Math.Max(0, book.SpineDocumentPaths.Count - 1));
            _textPageIndex = Math.Max(0, position.PageIndex);
            ApplyReaderCanvas();
            Loaded += async (_, _) => await InitializeWebPreviewAsync();
            SizeChanged += async (_, _) => { if (_readerReady) await InstallPaginationAsync(); };
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
        _positions.SavePosition(_book.EpubPath, new(0, _pageIndex));
    }

    private async Task InitializeWebPreviewAsync()
    {
        _webUserDataDirectory = Path.Combine(Path.GetTempPath(), "MobiVerseWebView", Guid.NewGuid().ToString("N"));
        _webEnvironment = await CoreWebView2Environment.CreateAsync(PortableRuntime.WebView2ExecutableFolder(), _webUserDataDirectory);
        await WebPreview.EnsureCoreWebView2Async(_webEnvironment);
        var settings = WebPreview.CoreWebView2.Settings;
        settings.IsScriptEnabled = false;
        settings.AreDefaultScriptDialogsEnabled = false;
        settings.AreDevToolsEnabled = false;
        settings.AreDefaultContextMenusEnabled = false;
        settings.IsStatusBarEnabled = false;
        WebPreview.CoreWebView2.AddWebResourceRequestedFilter("http://*", CoreWebView2WebResourceContext.All);
        WebPreview.CoreWebView2.AddWebResourceRequestedFilter("https://*", CoreWebView2WebResourceContext.All);
        WebPreview.CoreWebView2.WebResourceRequested += (_, args) =>
            args.Response = _webEnvironment.CreateWebResourceResponse(Stream.Null, 403, "Blocked", "Content-Type: text/plain");
        WebPreview.CoreWebView2.NavigationStarting += (_, args) =>
        {
            if (!Uri.TryCreate(args.Uri, UriKind.Absolute, out var uri) || !uri.IsFile || !EpubPathSecurity.Contains(uri.LocalPath, _book.ExtractionDirectory)) args.Cancel = true;
        };
        WebPreview.CoreWebView2.NavigationCompleted += async (_, args) => { if (args.IsSuccess) await InstallPaginationAsync(); };
        _readerReady = true;
        LoadTextSection();
    }

    private void LoadTextSection()
    {
        if (!_readerReady || _book.SpineDocumentPaths.Count == 0) return;
        _sectionIndex = Math.Clamp(_sectionIndex, 0, _book.SpineDocumentPaths.Count - 1);
        WebPreview.Source = new Uri(_book.SpineDocumentPaths[_sectionIndex]);
        UpdateTextControls();
    }

    private async Task InstallPaginationAsync()
    {
        if (!_readerReady || WebPreview.CoreWebView2 is null) return;
        var theme = ReaderColors.For(_readerPreferences.Theme);
        var fontSize = 18 * Math.Clamp(_readerPreferences.FontScale, .86, 1.32);
        var lineHeight = Math.Clamp(_readerPreferences.LineHeight, 1.45, 1.85);
        var script = $$"""
(() => {
  let style = document.getElementById('mobiverse-pagination-style');
  if (!style) { style = document.createElement('style'); style.id = 'mobiverse-pagination-style'; document.head.appendChild(style); }
  style.textContent = `
    html,body{width:100%!important;height:100%!important;min-height:100%!important;margin:0!important;padding:0!important;overflow:hidden!important;background:{{theme.Page}}!important;color:{{theme.Ink}}!important}
    #mobiverse-reader-pages{box-sizing:border-box!important;width:100vw!important;height:100vh!important;padding:clamp(28px,5vh,56px) var(--mv-side)!important;overflow:visible!important;column-width:calc(100vw - (2 * var(--mv-side)))!important;column-gap:calc(2 * var(--mv-side))!important;column-fill:auto!important;transform:translateX(calc(-1 * var(--mv-page) * 100vw));transition:transform 180ms ease-out;color:{{theme.Ink}}!important;font-family:Palatino Linotype,Palatino,Georgia,serif!important;font-size:{{fontSize.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture)}}px!important;line-height:{{lineHeight.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture)}}!important;letter-spacing:.008em!important;text-rendering:optimizeLegibility;font-kerning:normal;hyphens:auto}
    #mobiverse-reader-pages p,#mobiverse-reader-pages li,#mobiverse-reader-pages blockquote{color:{{theme.Ink}}!important;font-family:inherit!important;font-size:1em!important;line-height:inherit!important;orphans:3;widows:3}
    #mobiverse-reader-pages p{margin-top:0!important;margin-bottom:0!important;text-indent:1.35em!important}
    #mobiverse-reader-pages h1+p,#mobiverse-reader-pages h2+p,#mobiverse-reader-pages h3+p,#mobiverse-reader-pages .first,#mobiverse-reader-pages .noindent,#mobiverse-reader-pages p:first-child{text-indent:0!important}
    #mobiverse-reader-pages h1,#mobiverse-reader-pages h2,#mobiverse-reader-pages h3,#mobiverse-reader-pages h4{color:{{theme.Ink}}!important;font-family:Palatino Linotype,Palatino,Georgia,serif!important;font-weight:600!important;break-after:avoid}
    #mobiverse-reader-pages blockquote{color:{{theme.Muted}}!important;border-left:2px solid {{theme.Accent}}!important;margin:1.1em 1.5em!important;padding-left:1em!important}
    #mobiverse-reader-pages a{color:{{theme.Accent}}!important;text-decoration-thickness:.06em;text-underline-offset:.15em}
    #mobiverse-reader-pages [role=doc-pagebreak]{display:none!important}
    #mobiverse-reader-pages img,#mobiverse-reader-pages svg{display:block!important;margin-left:auto!important;margin-right:auto!important;max-width:calc(100vw - (2 * var(--mv-side)))!important;max-height:calc(100vh - clamp(56px,10vh,112px))!important;object-fit:contain!important;break-inside:avoid!important}
    #mobiverse-reader-pages figure,#mobiverse-reader-pages .media-rw,#mobiverse-reader-pages .image-rw,#mobiverse-reader-pages p.img{text-align:center!important;margin-left:auto!important;margin-right:auto!important;break-inside:avoid!important}
  `;
  let pages=document.getElementById('mobiverse-reader-pages');
  if(!pages){pages=document.createElement('div');pages.id='mobiverse-reader-pages';Array.from(document.body.childNodes).filter(n=>n!==style).forEach(n=>pages.appendChild(n));document.body.appendChild(pages)}
  const pageWidth=Math.min(760,Math.max(360,window.innerWidth-96));
  const side=Math.max(48,(window.innerWidth-pageWidth)/2);
  pages.style.setProperty('--mv-side',`${side}px`);pages.style.setProperty('--mv-page','0');
  const count=Math.max(1,Math.ceil((pages.scrollWidth-1)/Math.max(window.innerWidth,1)));
  window.__mobiversePageCount=count;
  window.__mobiverseSetPage=index=>{const safe=Math.max(0,Math.min(Number(index)||0,count-1));pages.style.setProperty('--mv-page',String(safe));return safe};
  return count;
})();
""";
        try
        {
            var result = await WebPreview.CoreWebView2.ExecuteScriptAsync(script);
            _textPageCount = int.TryParse(result.Trim('"'), out var count) ? Math.Max(1, count) : 1;
            if (_openLastPage) { _textPageIndex = _textPageCount - 1; _openLastPage = false; }
            _textPageIndex = Math.Clamp(_textPageIndex, 0, _textPageCount - 1);
            await ShowTextPageAsync();
        }
        catch { _textPageCount = 1; UpdateTextControls(); }
    }

    private async Task ShowTextPageAsync()
    {
        if (!_readerReady || WebPreview.CoreWebView2 is null) return;
        _textPageIndex = Math.Clamp(_textPageIndex, 0, Math.Max(0, _textPageCount - 1));
        await WebPreview.CoreWebView2.ExecuteScriptAsync($"window.__mobiverseSetPage?.({_textPageIndex});");
        _positions.SavePosition(_book.EpubPath, new(_sectionIndex, _textPageIndex));
        UpdateTextControls();
    }

    private async Task MoveTextAsync(int delta)
    {
        if (delta < 0)
        {
            if (_textPageIndex > 0) _textPageIndex--;
            else if (_sectionIndex > 0) { _sectionIndex--; _textPageIndex = 0; _textPageCount = 1; _openLastPage = true; LoadTextSection(); return; }
            else return;
        }
        else
        {
            if (_textPageIndex < _textPageCount - 1) _textPageIndex++;
            else if (_sectionIndex < _book.SpineDocumentPaths.Count - 1) { _sectionIndex++; _textPageIndex = 0; _textPageCount = 1; LoadTextSection(); return; }
            else return;
        }
        await ShowTextPageAsync();
    }

    private void UpdateTextControls()
    {
        var sections = Math.Max(1, _book.SpineDocumentPaths.Count);
        var overall = Math.Clamp((_sectionIndex + (double)(_textPageIndex + 1) / Math.Max(1, _textPageCount)) / sections, 0, 1);
        SectionBadge.Text = $"SECTION {_sectionIndex + 1} OF {sections}";
        TextPageBadge.Text = $"PAGE {_textPageIndex + 1} OF {_textPageCount}";
        TextPositionLabel.Text = $"Section {_sectionIndex + 1} · Page {_textPageIndex + 1}";
        TextProgress.Value = overall;
        TextProgressLabel.Text = $"{overall:P0}";
        TextPreviousButton.IsEnabled = _textPageIndex > 0 || _sectionIndex > 0;
        TextNextButton.IsEnabled = _textPageIndex < _textPageCount - 1 || _sectionIndex < _book.SpineDocumentPaths.Count - 1;
    }

    private void ApplyReaderCanvas()
    {
        var colors = ReaderColors.For(_readerPreferences.Theme);
        ReaderCanvas.Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(colors.Canvas));
        TextPageBorder.Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(colors.Page));
        var badge = new SolidColorBrush((Color)ColorConverter.ConvertFromString(colors.Muted));
        SectionBadge.Foreground = badge; TextPageBadge.Foreground = badge;
    }

    private void Move(int delta) { if (_book.Kind == EpubPreviewKind.ImagePages) { _pageIndex = Math.Clamp(_pageIndex + delta, 0, _book.ImagePages.Count - 1); ShowPage(); } }
    private void Previous_Click(object sender, RoutedEventArgs e) => Move(-1);
    private void Next_Click(object sender, RoutedEventArgs e) => Move(1);
    private async void TextPrevious_Click(object sender, RoutedEventArgs e) => await MoveTextAsync(-1);
    private async void TextNext_Click(object sender, RoutedEventArgs e) => await MoveTextAsync(1);
    private void PageSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e) { if (IsLoaded && _book.Kind == EpubPreviewKind.ImagePages) { _pageIndex = (int)Math.Round(e.NewValue); ShowPage(); } }
    private void Zoom(double amount) { _zoom = Math.Clamp(_zoom + amount, .5, 3); ImageScale.ScaleX = _zoom; ImageScale.ScaleY = _zoom; }
    private void ZoomOut_Click(object sender, RoutedEventArgs e) => Zoom(-.1);
    private void ZoomIn_Click(object sender, RoutedEventArgs e) => Zoom(.1);
    private void Fit_Click(object sender, RoutedEventArgs e) { _zoom = 1; ImageScale.ScaleX = 1; ImageScale.ScaleY = 1; }
    private void Close_Click(object sender, RoutedEventArgs e) => Close();
    private void ToggleAppearance_Click(object sender, RoutedEventArgs e) => AppearancePanel.Visibility = AppearancePanel.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible;
    private async void ReaderTheme_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is string value && Enum.TryParse<TextReaderTheme>(value, out var theme)) _readerPreferences.Theme = theme;
        SaveReaderPreferences(); ApplyReaderCanvas(); await InstallPaginationAsync();
    }
    private async void ReaderAppearance_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!_readerReady) return;
        _readerPreferences.FontScale = FontScaleSlider.Value;
        _readerPreferences.LineHeight = LineHeightSlider.Value;
        SaveReaderPreferences(); await InstallPaginationAsync();
    }
    private async void RestoreReaderDefaults_Click(object sender, RoutedEventArgs e)
    {
        _readerPreferences = new(); FontScaleSlider.Value = 1; LineHeightSlider.Value = 1.64;
        SaveReaderPreferences(); ApplyReaderCanvas(); await InstallPaginationAsync();
    }
    private void SaveReaderPreferences() => _readerStore.Save(_readerPreferences);

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

    private async void Window_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Left) { if (_book.Kind == EpubPreviewKind.ImagePages) Move(-1); else await MoveTextAsync(-1); e.Handled = true; }
        else if (e.Key == Key.Right) { if (_book.Kind == EpubPreviewKind.ImagePages) Move(1); else await MoveTextAsync(1); e.Handled = true; }
        else if (e.Key == Key.Escape && WindowStyle == WindowStyle.None) { FullScreen_Click(sender, e); e.Handled = true; }
    }

    private async void Window_PreviewMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (_book.Kind == EpubPreviewKind.ImagePages)
        {
            if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) Zoom(e.Delta > 0 ? .1 : -.1);
            else Move(e.Delta > 0 ? -1 : 1);
        }
        else if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control))
        {
            FontScaleSlider.Value = Math.Clamp(FontScaleSlider.Value + (e.Delta > 0 ? .04 : -.04), FontScaleSlider.Minimum, FontScaleSlider.Maximum);
        }
        else await MoveTextAsync(e.Delta > 0 ? -1 : 1);
        e.Handled = true;
    }

    private void Window_Closed(object? sender, EventArgs e)
    {
        if (_book.Kind == EpubPreviewKind.Web) _positions.SavePosition(_book.EpubPath, new(_sectionIndex, _textPageIndex));
        WebPreview.Dispose();
        try { Directory.Delete(_book.ExtractionDirectory, true); } catch { }
        if (_webUserDataDirectory is not null) try { Directory.Delete(_webUserDataDirectory, true); } catch { }
    }
}

public enum TextReaderTheme { Paper, Sepia, Night }

public sealed class ReaderPreferences
{
    public TextReaderTheme Theme { get; set; } = TextReaderTheme.Paper;
    public double FontScale { get; set; } = 1;
    public double LineHeight { get; set; } = 1.64;
}

public sealed class ReaderPreferencesStore
{
    private readonly string _path;
    public ReaderPreferencesStore(string? path = null) => _path = path ?? AppPaths.DataFile("reader-preferences.json");
    public ReaderPreferences Load() { try { return File.Exists(_path) ? JsonSerializer.Deserialize<ReaderPreferences>(File.ReadAllText(_path)) ?? new() : new(); } catch { return new(); } }
    public void Save(ReaderPreferences value) { try { Directory.CreateDirectory(Path.GetDirectoryName(_path)!); File.WriteAllText(_path, JsonSerializer.Serialize(value)); } catch { } }
}

public sealed record ReaderColors(string Page, string Canvas, string Ink, string Muted, string Accent)
{
    public static ReaderColors For(TextReaderTheme theme) => theme switch
    {
        TextReaderTheme.Sepia => new("#F0DFB8", "#C2AD8A", "#3D3024", "#796A57", "#7A4930"),
        TextReaderTheme.Night => new("#1B2324", "#0B0F11", "#E1DFD2", "#AAB2AE", "#D78A70"),
        _ => new("#FBF8EF", "#E3DFD1", "#223034", "#677174", "#8F4935")
    };
}
