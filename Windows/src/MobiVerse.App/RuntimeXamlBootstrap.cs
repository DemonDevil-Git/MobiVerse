#if RUNTIME_XAML
using Microsoft.Web.WebView2.Wpf;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Media3D;

namespace MobiVerse.App;

internal static class RuntimeXaml
{
    private static readonly Regex CodeBehindAttribute = new(
        "\\s(?:Click|SelectionChanged|KeyDown|MouseDoubleClick|ValueChanged|PreviewKeyDown|PreviewMouseWheel|Drop|DragOver|Executed)\\s*=\\s*\"[^\"]*\"",
        RegexOptions.Compiled);

    internal static T Load<T>(string fileName) where T : DependencyObject
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Xaml", fileName);
        var xaml = File.ReadAllText(path);
        xaml = Regex.Replace(xaml, "\\s+x:Class=\"[^\"]+\"", "");
        xaml = CodeBehindAttribute.Replace(xaml, "");
        xaml = xaml.Replace("clr-namespace:MobiVerse.App\"", "clr-namespace:MobiVerse.App;assembly=MobiVerse\"", StringComparison.Ordinal);
        return (T)XamlReader.Parse(xaml, new ParserContext { BaseUri = new Uri(path) });
    }

    internal static void Adopt(Window target, Window source)
    {
        target.Title = source.Title;
        target.Width = source.Width; target.Height = source.Height;
        target.MinWidth = source.MinWidth; target.MinHeight = source.MinHeight;
        target.Background = source.Background; target.Foreground = source.Foreground;
        target.AllowDrop = source.AllowDrop;
        var content = source.Content;
        source.Content = null;
        target.Content = content;
    }

    internal static void Adopt(UserControl target, UserControl source)
    {
        target.Background = source.Background; target.Foreground = source.Foreground;
        var content = source.Content;
        source.Content = null;
        target.Content = content;
    }

    internal static T Named<T>(FrameworkElement root, string name) where T : class =>
        (T)(root.FindName(name) ?? throw new InvalidDataException($"Runtime XAML is missing '{name}'."));

    internal static Button? ButtonFrom(RoutedEventArgs e)
    {
        if (e.Source is Button sourceButton) return sourceButton;
        var current = e.OriginalSource as DependencyObject;
        while (current is not null)
        {
            if (current is Button button) return button;
            current = current switch
            {
                Visual or Visual3D => VisualTreeHelper.GetParent(current),
                FrameworkContentElement content => content.Parent,
                _ => LogicalTreeHelper.GetParent(current)
            };
        }
        return null;
    }
}

public partial class App
{
    [STAThread]
    public static void Main()
    {
        var app = new App();
        app.InitializeComponent();
        app.Run(new MainWindow());
    }

    private void InitializeComponent()
    {
        Resources["Ink"] = new SolidColorBrush(Color.FromRgb(0x14, 0x2A, 0x33));
        Resources["Paper"] = new SolidColorBrush(Color.FromRgb(0xF6, 0xF2, 0xE8));
        Resources["Sidebar"] = new SolidColorBrush(Color.FromRgb(0xF8, 0xF5, 0xEE));
        Resources["Sage"] = new SolidColorBrush(Color.FromRgb(0x4F, 0x7A, 0x4F));
        Resources["Terracotta"] = new SolidColorBrush(Color.FromRgb(0xB8, 0x47, 0x29));
        Resources["Cobalt"] = new SolidColorBrush(Color.FromRgb(0x2E, 0x59, 0x73));
        var buttonStyle = new Style(typeof(Button));
        buttonStyle.Setters.Add(new Setter(Control.FontFamilyProperty, new FontFamily("Segoe UI")));
        buttonStyle.Setters.Add(new Setter(FrameworkElement.CursorProperty, Cursors.Hand));
        buttonStyle.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(12, 7, 12, 7)));
        buttonStyle.Setters.Add(new Setter(FrameworkElement.MarginProperty, new Thickness(0, 3, 0, 3)));
        Resources.Add(typeof(Button), buttonStyle);
        var textStyle = new Style(typeof(TextBlock));
        textStyle.Setters.Add(new Setter(Control.FontFamilyProperty, new FontFamily("Segoe UI")));
        Resources.Add(typeof(TextBlock), textStyle);
    }
}

public partial class MainWindow
{
    internal ColumnDefinition SidebarColumn = null!;
    internal Button PendingImportsButton = null!;
    internal Image ReadingArt = null!;
    internal Image HeroArt = null!;
    internal Button AppearanceButton = null!;
    internal Grid ShelfWorkspace = null!;
    internal BrowserWorkspace BrowseWorkspace = null!;
    internal Button ShelfWorkspaceButton = null!;
    internal Button BrowseWorkspaceButton = null!;
    internal TextBlock EmptyShelf = null!;
    internal Border BusyOverlay = null!;
    internal TextBlock BusyTitle = null!;
    internal TextBlock BusyMessage = null!;
    internal ProgressBar BusyProgress = null!;

    private void InitializeComponent()
    {
        var loaded = RuntimeXaml.Load<Window>("MainWindow.xaml");
        SidebarColumn = RuntimeXaml.Named<ColumnDefinition>(loaded, "SidebarColumn");
        PendingImportsButton = RuntimeXaml.Named<Button>(loaded, "PendingImportsButton");
        ReadingArt = RuntimeXaml.Named<Image>(loaded, "ReadingArt");
        HeroArt = RuntimeXaml.Named<Image>(loaded, "HeroArt");
        AppearanceButton = RuntimeXaml.Named<Button>(loaded, "AppearanceButton");
        ShelfWorkspace = RuntimeXaml.Named<Grid>(loaded, "ShelfWorkspace");
        BrowseWorkspace = RuntimeXaml.Named<BrowserWorkspace>(loaded, "BrowseWorkspace");
        ShelfWorkspaceButton = RuntimeXaml.Named<Button>(loaded, "ShelfWorkspaceButton");
        BrowseWorkspaceButton = RuntimeXaml.Named<Button>(loaded, "BrowseWorkspaceButton");
        EmptyShelf = RuntimeXaml.Named<TextBlock>(loaded, "EmptyShelf");
        BusyOverlay = RuntimeXaml.Named<Border>(loaded, "BusyOverlay");
        BusyTitle = RuntimeXaml.Named<TextBlock>(loaded, "BusyTitle");
        BusyMessage = RuntimeXaml.Named<TextBlock>(loaded, "BusyMessage");
        BusyProgress = RuntimeXaml.Named<ProgressBar>(loaded, "BusyProgress");
        RuntimeXaml.Adopt(this, loaded);
        AddHandler(Button.ClickEvent, new RoutedEventHandler(RuntimeButton_Click));
        DragOver += Window_DragOver; Drop += Window_Drop;
        KeyDown += async (_, e) => { if (e.Key == Key.O && Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) { await ChooseBooksAsync(); e.Handled = true; } };
    }

    private void RuntimeButton_Click(object sender, RoutedEventArgs e)
    {
        var button = RuntimeXaml.ButtonFrom(e); if (button is null) return;
        var content = button.Content?.ToString() ?? string.Empty;
        if (button.Tag is TaskItemViewModel)
        {
            if (button.Name == "PreviewButton" || content.Contains("Preview")) Preview_Click(button, e);
            else if (button.Name == "RevealButton" || content.Contains("Reveal")) Reveal_Click(button, e);
            else if (button.Name == "ReportButton" || content.Contains("Report")) Report_Click(button, e);
            else if (button.Name == "DeleteButton" || content.Contains('⌫')) Delete_Click(button, e);
            else return;
        }
        else if (button.Name == "ChooseBooksButton" || content.Contains("Choose books")) ChooseBooks_Click(button, e);
        else if (button.Name == "RetryFailedButton" || content.Contains("Retry failed")) RetryFailed_Click(button, e);
        else if (content.Contains("Review ")) ReviewImports_Click(button, e);
        else if (ReferenceEquals(button, ShelfWorkspaceButton)) ShelfWorkspace_Click(button, e);
        else if (ReferenceEquals(button, BrowseWorkspaceButton)) BrowseWorkspace_Click(button, e);
        else if (button.Name == "ToggleSidebarButton" || content == "☰") ToggleSidebar_Click(button, e);
        else if (button.Name == "RefreshToolsButton" || content == "✓") RefreshTools_Click(button, e);
        else if (button.Name == "GridViewButton" || content == "▦") GridView_Click(button, e);
        else if (button.Name == "ListViewButton" || content == "☷") ListView_Click(button, e);
        else if (content.Contains("System") || content.Contains("Light") || content.Contains("Dark")) Appearance_Click(button, e);
        else return;
        e.Handled = true;
    }
}

public partial class BrowserWorkspace
{
    internal TextBox AddressBox = null!;
    internal TabControl Tabs = null!;
    internal ColumnDefinition LibraryColumn = null!;
    internal ListBox BookmarksList = null!;
    internal CheckBox AutoPdfCheck = null!;
    internal TextBlock StatusText = null!;

    private void InitializeComponent()
    {
        var loaded = RuntimeXaml.Load<UserControl>("BrowserWorkspace.xaml");
        AddressBox = RuntimeXaml.Named<TextBox>(loaded, "AddressBox");
        Tabs = RuntimeXaml.Named<TabControl>(loaded, "Tabs");
        LibraryColumn = RuntimeXaml.Named<ColumnDefinition>(loaded, "LibraryColumn");
        BookmarksList = RuntimeXaml.Named<ListBox>(loaded, "BookmarksList");
        AutoPdfCheck = RuntimeXaml.Named<CheckBox>(loaded, "AutoPdfCheck");
        StatusText = RuntimeXaml.Named<TextBlock>(loaded, "StatusText");
        RuntimeXaml.Adopt(this, loaded);
        AddHandler(Button.ClickEvent, new RoutedEventHandler(RuntimeButton_Click));
        AddressBox.KeyDown += AddressBox_KeyDown;
        Tabs.SelectionChanged += Tabs_SelectionChanged;
        BookmarksList.MouseDoubleClick += BookmarksList_MouseDoubleClick;
        AutoPdfCheck.Click += AutoPdfCheck_Click;
    }

    private void RuntimeButton_Click(object sender, RoutedEventArgs e)
    {
        var button = RuntimeXaml.ButtonFrom(e); if (button is null) return;
        var content = button.Content?.ToString() ?? string.Empty;
        if (button.Tag is DownloadItemViewModel)
        {
            if (content == "Pause") PauseDownload_Click(button, e); else if (content == "Resume") ResumeDownload_Click(button, e);
            else if (content == "Cancel") CancelDownload_Click(button, e); else if (content == "Reveal") RevealDownload_Click(button, e); else return;
        }
        else if (button.Tag is BrowserBookmark) RemoveBookmark_Click(button, e);
        else if (content == "⌂") Home_Click(button, e); else if (content == "←") Back_Click(button, e);
        else if (content == "→") Forward_Click(button, e); else if (content == "↻") Reload_Click(button, e);
        else if (content == "Go") Go_Click(button, e); else if (content == "☆") Bookmark_Click(button, e);
        else if (content == "＋") NewTab_Click(button, e); else if (content == "☰") Library_Click(button, e);
        else if (content == "✕") CloseLibrary_Click(button, e); else if (content == "Choose download folder…") ChooseDownloadFolder_Click(button, e);
        else if (content == "Open downloads") OpenDownloads_Click(button, e); else if (content == "Clear browsing data") ClearBrowsingData_Click(button, e);
        else if (content == "Automatically download main-page PDFs") AutoPdfCheck_Click(button, e); else return;
        e.Handled = true;
    }
}

public partial class ImportReviewWindow
{
    internal Button ConfirmButton = null!;

    private void InitializeComponent()
    {
        var loaded = RuntimeXaml.Load<Window>("ImportReviewWindow.xaml");
        ConfirmButton = RuntimeXaml.Named<Button>(loaded, "ConfirmButton");
        RuntimeXaml.Adopt(this, loaded);
        AddHandler(Button.ClickEvent, new RoutedEventHandler(RuntimeButton_Click));
        AddHandler(Selector.SelectionChangedEvent, new SelectionChangedEventHandler(Selection_Changed));
    }

    private void RuntimeButton_Click(object sender, RoutedEventArgs e)
    {
        var button = RuntimeXaml.ButtonFrom(e); if (button is null) return;
        if (ReferenceEquals(button, ConfirmButton)) Confirm_Click(button, e);
        else if (button.Content?.ToString() == "Cancel") Cancel_Click(button, e);
        else return;
        e.Handled = true;
    }
}

public partial class PreviewWindow
{
    internal TextBlock TitleLabel = null!;
    internal TextBlock ModeLabel = null!;
    internal Button FullScreenButton = null!;
    internal ScrollViewer ImageScroller = null!;
    internal Image PageImage = null!;
    internal ScaleTransform ImageScale = null!;
    internal Border TextPageBorder = null!;
    internal WebView2 WebPreview = null!;
    internal Grid ReaderPositionBadge = null!;
    internal TextBlock SectionBadge = null!;
    internal TextBlock TextPageBadge = null!;
    internal Border AppearancePanel = null!;
    internal Slider FontScaleSlider = null!;
    internal Slider LineHeightSlider = null!;
    internal Border ImageControls = null!;
    internal Slider PageSlider = null!;
    internal TextBlock PageLabel = null!;
    internal Button PreviousButton = null!;
    internal Button NextButton = null!;
    internal Border TextControls = null!;
    internal ProgressBar TextProgress = null!;
    internal TextBlock TextPositionLabel = null!;
    internal TextBlock TextProgressLabel = null!;
    internal Button TextPreviousButton = null!;
    internal Button TextNextButton = null!;
    internal Grid ReaderCanvas = null!;

    private void InitializeComponent()
    {
        var loaded = RuntimeXaml.Load<Window>("PreviewWindow.xaml");
        TitleLabel = RuntimeXaml.Named<TextBlock>(loaded, "TitleLabel"); ModeLabel = RuntimeXaml.Named<TextBlock>(loaded, "ModeLabel");
        FullScreenButton = RuntimeXaml.Named<Button>(loaded, "FullScreenButton"); ImageScroller = RuntimeXaml.Named<ScrollViewer>(loaded, "ImageScroller");
        PageImage = RuntimeXaml.Named<Image>(loaded, "PageImage"); ImageScale = RuntimeXaml.Named<ScaleTransform>(loaded, "ImageScale");
        TextPageBorder = RuntimeXaml.Named<Border>(loaded, "TextPageBorder"); WebPreview = RuntimeXaml.Named<WebView2>(loaded, "WebPreview");
        ReaderPositionBadge = RuntimeXaml.Named<Grid>(loaded, "ReaderPositionBadge"); SectionBadge = RuntimeXaml.Named<TextBlock>(loaded, "SectionBadge");
        TextPageBadge = RuntimeXaml.Named<TextBlock>(loaded, "TextPageBadge"); AppearancePanel = RuntimeXaml.Named<Border>(loaded, "AppearancePanel");
        FontScaleSlider = RuntimeXaml.Named<Slider>(loaded, "FontScaleSlider"); LineHeightSlider = RuntimeXaml.Named<Slider>(loaded, "LineHeightSlider");
        ImageControls = RuntimeXaml.Named<Border>(loaded, "ImageControls"); PageSlider = RuntimeXaml.Named<Slider>(loaded, "PageSlider");
        PageLabel = RuntimeXaml.Named<TextBlock>(loaded, "PageLabel"); PreviousButton = RuntimeXaml.Named<Button>(loaded, "PreviousButton"); NextButton = RuntimeXaml.Named<Button>(loaded, "NextButton");
        TextControls = RuntimeXaml.Named<Border>(loaded, "TextControls"); TextProgress = RuntimeXaml.Named<ProgressBar>(loaded, "TextProgress");
        TextPositionLabel = RuntimeXaml.Named<TextBlock>(loaded, "TextPositionLabel"); TextProgressLabel = RuntimeXaml.Named<TextBlock>(loaded, "TextProgressLabel");
        TextPreviousButton = RuntimeXaml.Named<Button>(loaded, "TextPreviousButton"); TextNextButton = RuntimeXaml.Named<Button>(loaded, "TextNextButton");
        ReaderCanvas = RuntimeXaml.Named<Grid>(loaded, "ReaderCanvas");
        RuntimeXaml.Adopt(this, loaded);
        AddHandler(Button.ClickEvent, new RoutedEventHandler(RuntimeButton_Click));
        PageSlider.ValueChanged += PageSlider_ValueChanged; FontScaleSlider.ValueChanged += ReaderAppearance_ValueChanged; LineHeightSlider.ValueChanged += ReaderAppearance_ValueChanged;
        PreviewKeyDown += Window_PreviewKeyDown; PreviewMouseWheel += Window_PreviewMouseWheel;
    }

    private void RuntimeButton_Click(object sender, RoutedEventArgs e)
    {
        var button = RuntimeXaml.ButtonFrom(e); if (button is null) return;
        var content = button.Content?.ToString() ?? string.Empty;
        if (ReferenceEquals(button, FullScreenButton)) FullScreen_Click(button, e); else if (content == "✕") Close_Click(button, e);
        else if (ReferenceEquals(button, PreviousButton)) Previous_Click(button, e); else if (ReferenceEquals(button, NextButton)) Next_Click(button, e);
        else if (ReferenceEquals(button, TextPreviousButton)) TextPrevious_Click(button, e); else if (ReferenceEquals(button, TextNextButton)) TextNext_Click(button, e);
        else if (content == "−") ZoomOut_Click(button, e); else if (content == "＋") ZoomIn_Click(button, e); else if (content == "Fit") Fit_Click(button, e);
        else if (button.Tag is string && (content == "Paper" || content == "Sepia" || content == "Night")) ReaderTheme_Click(button, e);
        else if (content.Contains("Reading appearance")) ToggleAppearance_Click(button, e); else if (content == "Restore defaults") RestoreReaderDefaults_Click(button, e); else return;
        e.Handled = true;
    }
}
#endif
