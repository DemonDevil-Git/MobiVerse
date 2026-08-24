using Microsoft.Win32;
using MobiVerse.Core;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace MobiVerse.App;

public partial class MainWindow : Window, INotifyPropertyChanged
{
    private readonly IHistoryStore _historyStore = new HistoryStore(AppPaths.DataFile("history.json"));
    private readonly FileOutputPolicy _outputPolicy = new();
    private readonly ProcessRunner _runner = new();
    private readonly EpubArchiveService _archiveService = new();
    private readonly ImportReviewStore _importReviewStore = new(AppPaths.DataFile("pending-imports.json"));
    private readonly List<PendingImportViewModel> _pendingImports;
    private readonly ToolchainLocator _toolchainLocator;
    private readonly ConverterService _converter;
    private readonly HashSet<Guid> _previewWhenComplete = [];
    private bool _processing;
    private bool _isGrid = true;
    private double _cardWidth = 430;
    private ToolchainAvailability _tools;

    public MainWindow()
    {
        InitializeComponent();
        DataContext = this;
        var applicationDirectory = AppContext.BaseDirectory;
        _toolchainLocator = new ToolchainLocator(applicationDirectory);
        _tools = _toolchainLocator.Inspect();
        _converter = new ConverterService(_runner, _toolchainLocator, new WindowsPdfPageRenderer(), _archiveService);
        _pendingImports = _importReviewStore.Load();
        foreach (var task in _historyStore.Load()) Items.Add(new TaskItemViewModel(task));
        BrowseWorkspace.BookDownloaded += async (_, path) => await AnalyzeImportsAsync([path], ImportSource.BrowserDownload);
        Loaded += Window_Loaded;
        SizeChanged += (_, _) => UpdateCardWidth();
        AppThemeManager.ApplySaved(AppearanceButton);
        UpdateReadingArt();
        UpdatePresentation();
    }

    public ObservableCollection<TaskItemViewModel> Items { get; } = [];
    public int TotalCount => Items.Count;
    public int SucceededCount => Items.Count(item => item.Model.Status is ConversionStatus.Succeeded or ConversionStatus.SucceededWithWarnings);
    public int FailedCount => Items.Count(item => item.Model.Status == ConversionStatus.Failed);
    public int ActiveCount => Items.Count(item => item.Model.Status is ConversionStatus.Queued or ConversionStatus.CheckingTools or ConversionStatus.Converting or ConversionStatus.Validating);
    public string ToolStatusText => _tools.HasCalibre ? "●  Ready to convert" : "▲  Converter unavailable";
    public Brush ToolStatusBrush => _tools.HasCalibre ? (Brush)FindResource("Sage") : Brushes.DarkOrange;
    public double CardWidth { get => _cardWidth; private set { _cardWidth = value; OnPropertyChanged(); } }

    public event PropertyChangedEventHandler? PropertyChanged;

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        await LoadCachedCoversAsync();
        if (App.StartupFiles.Count > 0) await AnalyzeImportsAsync(App.StartupFiles, ImportSource.FilePicker);
        else if (_pendingImports.Count > 0) ShowImportReview();
        await ProcessQueueAsync();
    }

    private async void ChooseBooks_Click(object sender, RoutedEventArgs e) => await ChooseBooksAsync();
    private async void Open_Executed(object sender, ExecutedRoutedEventArgs e) => await ChooseBooksAsync();

    private async Task ChooseBooksAsync()
    {
        var dialog = new OpenFileDialog
        {
            Multiselect = true,
            Title = "Choose books",
            Filter = "Books|*.epub;*.mobi;*.azw;*.azw3;*.cbz;*.cbr;*.zip;*.pdf|All files|*.*"
        };
        if (dialog.ShowDialog(this) == true) await AnalyzeImportsAsync(dialog.FileNames, ImportSource.FilePicker);
    }

    private async Task AnalyzeImportsAsync(IEnumerable<string> paths, ImportSource source)
    {
        var supported = paths.Select(Path.GetFullPath)
            .Where(File.Exists)
            .Where(path => SupportedFormats.Openable.Contains(Path.GetExtension(path)))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Where(path => !_pendingImports.Any(item => item.Path.Equals(path, StringComparison.OrdinalIgnoreCase)))
            .ToArray();
        if (supported.Length == 0) return;

        BusyTitle.Text = "Analyzing imported books";
        BusyMessage.Text = "Detecting text and comic layouts locally";
        BusyProgress.Value = 0;
        BusyOverlay.Visibility = Visibility.Visible;
        var classifier = new BookClassifier(_runner, _toolchainLocator);
        try
        {
            for (var index = 0; index < supported.Length; index++)
            {
                var path = supported[index];
                BusyMessage.Text = $"Analyzing {Path.GetFileName(path)}";
                BusyProgress.Value = (double)index / supported.Length * 100;
                ClassificationResult classification;
                try { classification = await classifier.ClassifyAsync(path); }
                catch (Exception exception)
                {
                    classification = new(BookContentKind.Uncertain, 0, $"The file could not be classified: {exception.Message}");
                }
                _pendingImports.Add(new PendingImportViewModel(path, source, classification));
                _importReviewStore.Save(_pendingImports);
            }
        }
        finally
        {
            BusyOverlay.Visibility = Visibility.Collapsed;
            UpdatePendingImportsButton();
        }
        ShowImportReview();
    }

    private void ShowImportReview()
    {
        if (_pendingImports.Count == 0) return;
        var dialog = new ImportReviewWindow(_pendingImports) { Owner = this };
        var confirmed = dialog.ShowDialog() == true && dialog.Confirmed;
        _importReviewStore.Save(_pendingImports);
        if (!confirmed) { UpdatePendingImportsButton(); return; }

        string? firstEpub = null;
        foreach (var import in _pendingImports.ToArray())
        {
            var existing = Items.FirstOrDefault(item => item.Model.InputPath.Equals(import.Path, StringComparison.OrdinalIgnoreCase));
            if (import.IsEpub)
            {
                if (existing is null)
                {
                    existing = new TaskItemViewModel(new ConversionTask
                    {
                        InputPath = import.Path,
                        OutputPath = import.Path,
                        Status = ConversionStatus.Succeeded,
                        Progress = 1,
                        StatusMessage = "Ready to read",
                        CompletedAt = DateTimeOffset.Now,
                        ImportSource = import.Source,
                        DetectedKind = import.Classification.Kind,
                        ConversionProfile = import.SelectedProfile ?? ConversionProfile.TextReflow,
                        ReadingDirection = import.ReadingDirection
                    });
                    Items.Add(existing);
                    _ = LoadCoverAsync(existing);
                }
                firstEpub ??= import.Path;
                continue;
            }

            if (import.SelectedProfile is null) continue;
            if (existing is not null)
            {
                if (existing.Model.Status is ConversionStatus.Failed or ConversionStatus.Succeeded or ConversionStatus.SucceededWithWarnings)
                    Requeue(existing);
            }
            else
            {
                existing = new TaskItemViewModel(new ConversionTask { InputPath = import.Path });
                Items.Add(existing);
            }
            existing.Model.ImportSource = import.Source;
            existing.Model.DetectedKind = import.Classification.Kind;
            existing.Model.ConversionProfile = import.SelectedProfile.Value;
            existing.Model.ReadingDirection = import.ReadingDirection;
            _previewWhenComplete.Add(existing.Model.Id);
        }
        _pendingImports.Clear();
        _importReviewStore.Save(_pendingImports);
        UpdatePendingImportsButton();
        ShowShelfWorkspace();
        PersistAndRefresh();
        _ = ProcessQueueAsync();
        if (firstEpub is not null) _ = OpenPreviewAsync(firstEpub);
    }

    private async Task ProcessQueueAsync()
    {
        if (_processing) return;
        _processing = true;
        try
        {
            while (Items.FirstOrDefault(item => item.Model.Status == ConversionStatus.Queued) is { } item)
            {
                await ProcessItemAsync(item);
                if (_previewWhenComplete.Remove(item.Model.Id) && item.CanPreview) await OpenPreviewAsync(item.Model.OutputPath!);
            }
        }
        finally { _processing = false; UpdatePresentation(); }
    }

    private async Task ProcessItemAsync(TaskItemViewModel item)
    {
        var task = item.Model;
        AppDiagnostics.Write($"Conversion started. Input={task.InputPath}");
        task.Status = ConversionStatus.CheckingTools;
        task.Progress = .1;
        task.StatusMessage = Path.GetExtension(task.InputPath).Equals(".pdf", StringComparison.OrdinalIgnoreCase)
            ? "Preparing native PDF conversion" : "Checking Calibre and EPUBCheck";
        Update(item);
        _tools = _toolchainLocator.Inspect();
        var usesNativePdf = Path.GetExtension(task.InputPath).Equals(".pdf", StringComparison.OrdinalIgnoreCase) &&
                            task.ConversionProfile == ConversionProfile.ComicFixedLayout;
        if (!usesNativePdf && !_tools.HasCalibre)
        {
            Fail(item, "Bundled Calibre was not found. Reinstall MobiVerse or install Calibre.");
            return;
        }

        try
        {
            task.OutputPath = _outputPolicy.EpubOutputPath(task.InputPath);
            task.Status = ConversionStatus.Converting;
            task.Progress = .12;
            task.StatusMessage = "Converting to EPUB";
            Update(item);
            var progress = new Progress<ConversionProgressUpdate>(update =>
            {
                task.Progress = .12 + Math.Clamp(update.Fraction, 0, 1) * .66;
                task.StatusMessage = update.Message;
                Update(item, false);
            });
            var conversion = await _converter.ConvertAsync(
                task.InputPath,
                task.OutputPath,
                progress,
                profile: task.ConversionProfile,
                readingDirection: task.ReadingDirection);
            task.Log = conversion.Log;
            task.Status = ConversionStatus.Validating;
            task.Progress = .8;
            task.StatusMessage = "Running EPUBCheck";
            Update(item);
            task.ReportPath = _outputPolicy.ReportPath(task.OutputPath);
            var validation = await new EpubValidator(_runner, _tools.EpubCheckPath).ValidateAsync(
                task.OutputPath, task.ReportPath, conversion.Log, conversion.PostProcessReport ?? string.Empty);
            task.Progress = 1;
            task.CompletedAt = DateTimeOffset.Now;
            task.Status = validation.Status switch
            {
                EpubValidationStatus.Warnings => ConversionStatus.SucceededWithWarnings,
                EpubValidationStatus.Failed => ConversionStatus.Failed,
                _ => ConversionStatus.Succeeded
            };
            task.StatusMessage = validation.Status switch
            {
                EpubValidationStatus.Passed => "EPUB created and validated",
                EpubValidationStatus.Warnings => "EPUB created with validation warnings",
                EpubValidationStatus.Failed => "EPUBCheck failed. Review the report.",
                _ => "EPUB created. Open the report for validation details."
            };
            await LoadCoverAsync(item);
            Update(item);
            AppDiagnostics.Write($"Conversion completed. Input={task.InputPath}; Output={task.OutputPath}; Status={task.Status}");
        }
        catch (ConversionException exception) { AppDiagnostics.Write($"Conversion failed. Input={task.InputPath}", exception); Fail(item, exception.Message, exception.Log); }
        catch (UnauthorizedAccessException exception) { AppDiagnostics.Write($"Conversion access failure. Input={task.InputPath}", exception); Fail(item, "The app could not write the EPUB in the source folder. Check folder permissions.", exception.Message); }
        catch (Exception exception) { AppDiagnostics.Write($"Conversion failed unexpectedly. Input={task.InputPath}", exception); Fail(item, exception.Message, exception.ToString()); }
    }

    private void Fail(TaskItemViewModel item, string message, string log = "")
    {
        item.Model.Status = ConversionStatus.Failed;
        item.Model.Progress = 1;
        item.Model.StatusMessage = message;
        item.Model.Log = log;
        item.Model.CompletedAt = DateTimeOffset.Now;
        Update(item);
    }

    private void Update(TaskItemViewModel item, bool persist = true)
    {
        item.Refresh();
        if (persist) _historyStore.Save(Items.Select(value => value.Model).ToArray());
        UpdatePresentation();
    }

    private void PersistAndRefresh()
    {
        _historyStore.Save(Items.Select(item => item.Model).ToArray());
        UpdatePresentation();
    }

    private void UpdatePresentation()
    {
        EmptyShelf.Visibility = Items.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        OnPropertyChanged(nameof(TotalCount)); OnPropertyChanged(nameof(SucceededCount));
        OnPropertyChanged(nameof(FailedCount)); OnPropertyChanged(nameof(ActiveCount));
        OnPropertyChanged(nameof(ToolStatusText)); OnPropertyChanged(nameof(ToolStatusBrush));
        UpdatePendingImportsButton();
        UpdateCardWidth();
    }

    private void UpdatePendingImportsButton()
    {
        if (PendingImportsButton is null) return;
        PendingImportsButton.Visibility = _pendingImports.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        PendingImportsButton.Content = $"☑  Review {_pendingImports.Count} import{(_pendingImports.Count == 1 ? "" : "s")}";
    }

    private void UpdateCardWidth()
    {
        var contentWidth = Math.Max(700, ActualWidth - (SidebarColumn.Width.Value > 0 ? 286 : 0) - 70);
        if (!_isGrid) CardWidth = contentWidth;
        else
        {
            var columns = Math.Max(1, (int)(contentWidth / 390));
            CardWidth = Math.Max(340, (contentWidth - (columns - 1) * 14) / columns);
        }
    }

    private void RetryFailed_Click(object sender, RoutedEventArgs e)
    {
        foreach (var item in Items.Where(item => item.Model.Status == ConversionStatus.Failed)) Requeue(item);
        PersistAndRefresh();
        _ = ProcessQueueAsync();
    }

    private void Requeue(TaskItemViewModel item)
    {
        var coverPath = CoverCachePath(item.Model.Id);
        try { if (File.Exists(coverPath)) File.Delete(coverPath); } catch { }
        item.ClearCover();
        item.Model.Status = ConversionStatus.Queued;
        item.Model.Progress = 0;
        item.Model.StatusMessage = "Waiting";
        item.Model.OutputPath = null;
        item.Model.ReportPath = null;
        item.Model.CompletedAt = null;
        item.Refresh();
    }

    private async void Preview_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is TaskItemViewModel item && item.Model.OutputPath is not null)
            await OpenPreviewAsync(item.Model.OutputPath);
    }

    private static TaskItemViewModel? Tagged(object sender) => (sender as FrameworkElement)?.Tag as TaskItemViewModel;

    private void Reveal_Click(object sender, RoutedEventArgs e)
    {
        var path = Tagged(sender)?.Model.OutputPath;
        if (path is not null && File.Exists(path)) Process.Start(new ProcessStartInfo("explorer.exe") { ArgumentList = { "/select,", path }, UseShellExecute = true });
    }

    private void Report_Click(object sender, RoutedEventArgs e)
    {
        var path = Tagged(sender)?.Model.ReportPath;
        if (path is not null && File.Exists(path)) Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        var item = Tagged(sender);
        if (item is null)
        {
            AppDiagnostics.Write("Delete action ignored because the button had no bound conversion item.");
            return;
        }
        var hasOutput = item.Model.OutputPath is not null && File.Exists(item.Model.OutputPath);
        var message = hasOutput
            ? $"\"{Path.GetFileName(item.Model.OutputPath)}\" will be permanently deleted and removed from history."
            : "This conversion will be removed from your history.";
        if (MessageBox.Show(this, message, hasOutput ? "Delete local EPUB?" : "Remove conversion history?", MessageBoxButton.OKCancel, MessageBoxImage.Warning) != MessageBoxResult.OK) return;
        try { if (hasOutput) File.Delete(item.Model.OutputPath!); }
        catch (Exception exception) { MessageBox.Show(this, exception.Message, "Couldn’t delete EPUB", MessageBoxButton.OK, MessageBoxImage.Error); return; }
        Items.Remove(item);
        try { var coverPath = CoverCachePath(item.Model.Id); if (File.Exists(coverPath)) File.Delete(coverPath); } catch { }
        PersistAndRefresh();
    }

    private async Task OpenPreviewAsync(string epubPath)
    {
        if (!File.Exists(epubPath))
        {
            MessageBox.Show(this, "The EPUB is no longer available.", "Preview unavailable", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        BusyTitle.Text = Path.GetFileNameWithoutExtension(epubPath);
        BusyMessage.Text = "Opening EPUB preview";
        BusyProgress.Value = 35;
        BusyOverlay.Visibility = Visibility.Visible;
        try
        {
            var extraction = Path.Combine(Path.GetTempPath(), "MobiVersePreview", Guid.NewGuid().ToString("N"));
            var book = await Task.Run(() => new EpubPreviewParser().Parse(epubPath, extraction));
            BusyProgress.Value = 100;
            new PreviewWindow(book) { Owner = this }.Show();
        }
        catch (Exception exception) { MessageBox.Show(this, exception.Message, "Preview unavailable", MessageBoxButton.OK, MessageBoxImage.Error); }
        finally { BusyOverlay.Visibility = Visibility.Collapsed; }
    }

    private async Task LoadCachedCoversAsync()
    {
        foreach (var item in Items.Where(item => item.CanPreview)) await LoadCoverAsync(item);
    }

    private static async Task LoadCoverAsync(TaskItemViewModel item)
    {
        var epubPath = item.Model.OutputPath;
        if (epubPath is null || !File.Exists(epubPath)) return;
        var cacheDirectory = Path.GetDirectoryName(CoverCachePath(item.Model.Id))!;
        var cachePath = CoverCachePath(item.Model.Id);
        if (!File.Exists(cachePath))
        {
            var extraction = Path.Combine(Path.GetTempPath(), "MobiVerseCover", item.Model.Id.ToString("N"));
            try
            {
                var source = await Task.Run(() => new EpubPreviewParser().ExtractCover(epubPath, extraction));
                if (source is null) return;
                Directory.CreateDirectory(cacheDirectory);
                File.Copy(source, cachePath, true);
            }
            catch { return; }
            finally { try { Directory.Delete(extraction, true); } catch { } }
        }
        item.SetCover(cachePath);
    }

    private static string CoverCachePath(Guid id) => Path.Combine(
        AppPaths.DataDirectory, "CoverCache", id + ".cover");

    private void Window_DragOver(object sender, DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    private async void Window_Drop(object sender, DragEventArgs e)
    {
        if (e.Data.GetData(DataFormats.FileDrop) is string[] paths) await AnalyzeImportsAsync(paths, ImportSource.DragAndDrop);
    }

    private void ReviewImports_Click(object sender, RoutedEventArgs e) => ShowImportReview();
    private void ShelfWorkspace_Click(object sender, RoutedEventArgs e) => ShowShelfWorkspace();
    private void BrowseWorkspace_Click(object sender, RoutedEventArgs e)
    {
        ShelfWorkspace.Visibility = Visibility.Collapsed;
        BrowseWorkspace.Visibility = Visibility.Visible;
        ShelfWorkspaceButton.Background = Brushes.Transparent;
        ShelfWorkspaceButton.Foreground = (Brush)FindResource("Ink");
        BrowseWorkspaceButton.Background = (Brush)FindResource("Sage");
        BrowseWorkspaceButton.Foreground = Brushes.White;
    }

    private void ShowShelfWorkspace()
    {
        ShelfWorkspace.Visibility = Visibility.Visible;
        BrowseWorkspace.Visibility = Visibility.Collapsed;
        ShelfWorkspaceButton.Background = (Brush)FindResource("Sage");
        ShelfWorkspaceButton.Foreground = Brushes.White;
        BrowseWorkspaceButton.Background = Brushes.Transparent;
        BrowseWorkspaceButton.Foreground = (Brush)FindResource("Ink");
    }

    private void Appearance_Click(object sender, RoutedEventArgs e) { AppThemeManager.Cycle(AppearanceButton); UpdateReadingArt(); }
    private void UpdateReadingArt()
    {
        var fileName = AppThemeManager.IsDark ? "reading-still-life-dark.png" : "reading-still-life.png";
#if RUNTIME_XAML
        ReadingArt.Source = LoadLooseImage(fileName);
        HeroArt.Source = LoadLooseImage("hero-books-background.png");
#else
        ReadingArt.Source = new BitmapImage(new Uri($"pack://application:,,,/Resources/{fileName}"));
        HeroArt.Source = new BitmapImage(new Uri("pack://application:,,,/Resources/hero-books-background.png"));
#endif
    }
#if RUNTIME_XAML
    private static BitmapImage LoadLooseImage(string fileName)
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Resources", fileName);
        var bitmap = new BitmapImage();
        bitmap.BeginInit();
        bitmap.CacheOption = BitmapCacheOption.OnLoad;
        bitmap.UriSource = new Uri(path, UriKind.Absolute);
        bitmap.EndInit();
        bitmap.Freeze();
        return bitmap;
    }
#endif
    private void ToggleSidebar_Click(object sender, RoutedEventArgs e) { SidebarColumn.Width = SidebarColumn.Width.Value == 0 ? new GridLength(286) : new GridLength(0); UpdateCardWidth(); }
    private void GridView_Click(object sender, RoutedEventArgs e) { _isGrid = true; UpdateCardWidth(); }
    private void ListView_Click(object sender, RoutedEventArgs e) { _isGrid = false; UpdateCardWidth(); }
    private void RefreshTools_Click(object sender, RoutedEventArgs e) { _tools = _toolchainLocator.Inspect(); UpdatePresentation(); }
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
}

public sealed class TaskItemViewModel : INotifyPropertyChanged
{
    public TaskItemViewModel(ConversionTask model) => Model = model;
    public ConversionTask Model { get; }
    public string Title => Path.GetFileNameWithoutExtension(Model.InputPath);
    public string Extension => Path.GetExtension(Model.InputPath).TrimStart('.').ToUpperInvariant();
    public double ProgressPercent => Model.Progress * 100;
    public string StatusText => Model.Status switch
    {
        ConversionStatus.Succeeded => "●  Succeeded", ConversionStatus.SucceededWithWarnings => "●  Warnings",
        ConversionStatus.Failed => "●  Failed", _ => Model.Status.ToString()
    };
    public string DetailText => Model.CompletedAt is { } date ? $"Completed {date.LocalDateTime:g}" : Model.StatusMessage;
    public Brush StatusBrush => Model.Status switch
    {
        ConversionStatus.Failed => new SolidColorBrush(Color.FromRgb(184, 71, 41)),
        ConversionStatus.SucceededWithWarnings => Brushes.DarkOrange,
        ConversionStatus.Succeeded => new SolidColorBrush(Color.FromRgb(79, 122, 79)),
        _ => new SolidColorBrush(Color.FromRgb(46, 89, 115))
    };
    public Brush StatusBackground => new SolidColorBrush(Color.FromArgb(24, ((SolidColorBrush)StatusBrush).Color.R, ((SolidColorBrush)StatusBrush).Color.G, ((SolidColorBrush)StatusBrush).Color.B));
    public Brush CoverBrush => Extension switch
    {
        "AZW" or "AZW3" => new SolidColorBrush(Color.FromRgb(46, 89, 115)),
        "MOBI" => new SolidColorBrush(Color.FromRgb(79, 122, 79)),
        "CBZ" or "CBR" or "ZIP" or "PDF" => new SolidColorBrush(Color.FromRgb(184, 71, 41)),
        _ => new SolidColorBrush(Color.FromRgb(97, 54, 31))
    };
    public ImageSource? CoverImage { get; private set; }
    public bool CanPreview =>
        (Model.Status is ConversionStatus.Succeeded or ConversionStatus.SucceededWithWarnings) &&
        Model.OutputPath is not null && File.Exists(Model.OutputPath);
    public bool CanReveal => Model.OutputPath is not null && File.Exists(Model.OutputPath);
    public bool CanReport => Model.ReportPath is not null && File.Exists(Model.ReportPath);
    public bool CanDelete => Model.Status is not (ConversionStatus.CheckingTools or ConversionStatus.Converting or ConversionStatus.Validating);
    public event PropertyChangedEventHandler? PropertyChanged;

    public void SetCover(string path)
    {
        try
        {
            var bitmap = new BitmapImage();
            bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad; bitmap.UriSource = new Uri(path); bitmap.EndInit(); bitmap.Freeze();
            CoverImage = bitmap; OnPropertyChanged(nameof(CoverImage));
        }
        catch { }
    }

    public void ClearCover() { CoverImage = null; OnPropertyChanged(nameof(CoverImage)); }

    public void Refresh()
    {
        foreach (var property in new[] { nameof(ProgressPercent), nameof(StatusText), nameof(DetailText), nameof(StatusBrush), nameof(StatusBackground), nameof(CanPreview), nameof(CanReveal), nameof(CanReport), nameof(CanDelete) }) OnPropertyChanged(property);
    }

    private void OnPropertyChanged(string name) => PropertyChanged?.Invoke(this, new(name));
}

public enum AppAppearancePreference { System, Light, Dark }

public static class AppThemeManager
{
    private static readonly string StoragePath = Path.Combine(
        AppPaths.DataDirectory, "appearance.txt");
    private static AppAppearancePreference _preference = AppAppearancePreference.System;
    public static bool IsDark { get; private set; }

    public static void ApplySaved(Button label)
    {
        try
        {
            if (File.Exists(StoragePath) && Enum.TryParse<AppAppearancePreference>(File.ReadAllText(StoragePath), out var saved))
                _preference = saved;
        }
        catch { }
        Apply(label);
    }

    public static void Cycle(Button label)
    {
        _preference = _preference switch
        {
            AppAppearancePreference.System => AppAppearancePreference.Light,
            AppAppearancePreference.Light => AppAppearancePreference.Dark,
            _ => AppAppearancePreference.System
        };
        try { Directory.CreateDirectory(Path.GetDirectoryName(StoragePath)!); File.WriteAllText(StoragePath, _preference.ToString()); } catch { }
        Apply(label);
    }

    private static void Apply(Button label)
    {
        IsDark = _preference == AppAppearancePreference.Dark || (_preference == AppAppearancePreference.System && SystemUsesDarkTheme());
        SetColor("Ink", IsDark ? "#F0E9DB" : "#142A33");
        SetColor("Paper", IsDark ? "#171B1C" : "#F6F2E8");
        SetColor("Sidebar", IsDark ? "#202526" : "#F8F5EE");
        SetColor("Sage", IsDark ? "#80A77E" : "#4F7A4F");
        SetColor("Terracotta", IsDark ? "#DB7B5D" : "#B84729");
        SetColor("Cobalt", IsDark ? "#76A7C3" : "#2E5973");
        label.Content = $"◐  {_preference}";
    }

    private static void SetColor(string key, string value)
    {
        if (Application.Current.Resources[key] is SolidColorBrush brush && !brush.IsFrozen)
            brush.Color = (Color)ColorConverter.ConvertFromString(value);
    }

    private static bool SystemUsesDarkTheme()
    {
        try
        {
            var value = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")?.GetValue("AppsUseLightTheme");
            return value is int number && number == 0;
        }
        catch { return false; }
    }
}
