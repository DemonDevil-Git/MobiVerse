using MobiVerse.Core;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;

namespace MobiVerse.App;

public partial class ImportReviewWindow : Window
{
    public ImportReviewWindow(IReadOnlyList<PendingImportViewModel> items)
    {
        InitializeComponent();
        Items = items;
        DataContext = this;
        UpdateConfirmation();
    }

    public IReadOnlyList<PendingImportViewModel> Items { get; }
    public bool Confirmed { get; private set; }

    private void Selection_Changed(object sender, System.Windows.Controls.SelectionChangedEventArgs e) => UpdateConfirmation();
    private void UpdateConfirmation() => ConfirmButton.IsEnabled = Items.Count > 0 && Items.All(item => item.IsReady);
    private void Cancel_Click(object sender, RoutedEventArgs e) { DialogResult = false; Close(); }
    private void Confirm_Click(object sender, RoutedEventArgs e) { Confirmed = true; DialogResult = true; Close(); }
}

public sealed class PendingImportViewModel : INotifyPropertyChanged
{
    private ConversionProfile? _selectedProfile;

    public PendingImportViewModel(string path, ImportSource source, ClassificationResult classification)
    {
        Id = Guid.NewGuid();
        Path = path;
        Source = source;
        Classification = classification;
        _selectedProfile = classification.Kind switch
        {
            BookContentKind.Text => ConversionProfile.TextReflow,
            BookContentKind.Comic => ConversionProfile.ComicFixedLayout,
            _ => null
        };
    }

    [JsonConstructor]
    public PendingImportViewModel(Guid id, string path, ImportSource source, ClassificationResult classification,
        ConversionProfile? selectedProfile, EpubReadingDirection readingDirection)
    {
        Id = id;
        Path = path;
        Source = source;
        Classification = classification;
        _selectedProfile = selectedProfile;
        ReadingDirection = readingDirection;
    }

    public Guid Id { get; }
    public string Path { get; }
    public ImportSource Source { get; }
    public ClassificationResult Classification { get; }
    public string Title => System.IO.Path.GetFileNameWithoutExtension(Path);
    public bool IsEpub => System.IO.Path.GetExtension(Path).Equals(".epub", StringComparison.OrdinalIgnoreCase);
    public bool IsReady => IsEpub || SelectedProfile is not null;
    public EpubReadingDirection ReadingDirection { get; set; } = EpubReadingDirection.RightToLeft;
    public ConversionProfile? SelectedProfile
    {
        get => _selectedProfile;
        set
        {
            if (_selectedProfile == value) return;
            _selectedProfile = value;
            OnPropertyChanged(); OnPropertyChanged(nameof(IsReady)); OnPropertyChanged(nameof(DirectionVisibility));
        }
    }
    public Visibility DirectionVisibility => !IsEpub && SelectedProfile == ConversionProfile.ComicFixedLayout ? Visibility.Visible : Visibility.Collapsed;
    public Brush ConfidenceBrush => Classification.Kind == BookContentKind.Uncertain ? Brushes.DarkOrange : Brushes.Gray;
    public string ConfidenceLabel => $"{Classification.Kind switch { BookContentKind.Text => "Text book", BookContentKind.Comic => "Comic / image book", _ => "Needs your choice" }} · {Math.Round(Classification.Confidence * 100):0}% confidence";
    public IReadOnlyList<Choice<ConversionProfile?>> ProfileChoices { get; } =
    [
        new("Choose layout…", null), new("Text · Reflowable", ConversionProfile.TextReflow),
        new("Comic · Fixed layout", ConversionProfile.ComicFixedLayout)
    ];
    public IReadOnlyList<Choice<EpubReadingDirection>> DirectionChoices { get; } =
    [new("Right to left", EpubReadingDirection.RightToLeft), new("Left to right", EpubReadingDirection.LeftToRight)];

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
}

public sealed record Choice<T>(string Title, T Value);

public sealed class ImportReviewStore
{
    private readonly string _path;
    public ImportReviewStore(string? path = null) => _path = path ?? AppPaths.DataFile("pending-imports.json");
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter() }
    };

    public List<PendingImportViewModel> Load()
    {
        try
        {
            if (!File.Exists(_path)) return [];
            return (JsonSerializer.Deserialize<List<PendingImportViewModel>>(File.ReadAllText(_path), Options) ?? [])
                .Where(item => File.Exists(item.Path)).ToList();
        }
        catch { return []; }
    }

    public void Save(IReadOnlyList<PendingImportViewModel> items)
    {
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(_path)!);
            File.WriteAllText(_path, JsonSerializer.Serialize(items, Options));
        }
        catch { }
    }
}

public sealed class InverseBooleanToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is true ? Visibility.Collapsed : Visibility.Visible;
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => Binding.DoNothing;
}
