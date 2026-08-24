using System.Text.Json.Serialization;

namespace MobiVerse.Core;

public enum ConversionStatus
{
    Queued,
    CheckingTools,
    Converting,
    Validating,
    Succeeded,
    SucceededWithWarnings,
    Failed
}

public enum ConversionFailureKind
{
    MissingCalibre,
    DrmProtected,
    InputUnreadable,
    OutputPermissionDenied,
    ConversionFailed
}

public enum ConversionStrategy { Calibre, NativePdfFixedLayout }
public enum EpubValidationStatus { Passed, Warnings, Failed, Skipped }
public enum EpubReadingDirection { LeftToRight, RightToLeft }
public enum EpubPreviewKind { ImagePages, Web }
public enum BookContentKind { Text, Comic, Uncertain }
public enum ConversionProfile { TextReflow, ComicFixedLayout }
public enum ImportSource { BrowserDownload, FilePicker, DragAndDrop }

public sealed record ClassificationResult(BookContentKind Kind, double Confidence, string Evidence)
{
    public double Confidence { get; init; } = Math.Clamp(Confidence, 0, 1);
}

public sealed class ConversionTask
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public required string InputPath { get; init; }
    public string? OutputPath { get; set; }
    [JsonConverter(typeof(JsonStringEnumConverter))]
    public ConversionStatus Status { get; set; } = ConversionStatus.Queued;
    public double Progress { get; set; }
    public string StatusMessage { get; set; } = "Waiting";
    public string Log { get; set; } = string.Empty;
    public string? ReportPath { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }
    [JsonConverter(typeof(JsonStringEnumConverter))]
    public ImportSource? ImportSource { get; set; }
    [JsonConverter(typeof(JsonStringEnumConverter))]
    public BookContentKind? DetectedKind { get; set; }
    [JsonConverter(typeof(JsonStringEnumConverter))]
    public ConversionProfile ConversionProfile { get; set; } = ConversionProfile.ComicFixedLayout;
    [JsonConverter(typeof(JsonStringEnumConverter))]
    public EpubReadingDirection ReadingDirection { get; set; } = EpubReadingDirection.RightToLeft;
}

public sealed record ConversionProgressUpdate(
    double Fraction,
    string Message,
    int CompletedUnitCount,
    int TotalUnitCount);

public sealed record ConversionRunResult(
    string OutputPath,
    string Log,
    ConversionStrategy Strategy = ConversionStrategy.Calibre,
    string? PostProcessReport = null);

public sealed record ProcessRunResult(int ExitCode, string Output);

public sealed record ToolchainAvailability(
    string? EbookConvertPath,
    string? EbookMetaPath,
    string? EpubCheckPath,
    bool IsBundled)
{
    public bool HasCalibre => EbookConvertPath is not null && EbookMetaPath is not null;
}

public sealed record EpubImagePreviewPage(
    string Id,
    string Title,
    string ImagePath,
    int Width,
    int Height);

public sealed record EpubPreviewBook(
    string Title,
    string EpubPath,
    string ExtractionDirectory,
    string ContentRootDirectory,
    EpubReadingDirection ReadingDirection,
    EpubPreviewKind Kind,
    IReadOnlyList<EpubImagePreviewPage> ImagePages,
    IReadOnlyList<string> SpineDocumentPaths)
{
    public string? StartDocumentPath => SpineDocumentPaths.FirstOrDefault();
}

public sealed record PreviewReadingPosition(int SectionIndex, int PageIndex)
{
    public int SectionIndex { get; init; } = Math.Max(0, SectionIndex);
    public int PageIndex { get; init; } = Math.Max(0, PageIndex);
}

public sealed class ConversionException(
    ConversionFailureKind kind,
    string message,
    string log = "") : Exception(message)
{
    public ConversionFailureKind Kind { get; } = kind;
    public string Log { get; } = log;
}

public static class SupportedFormats
{
    public static readonly HashSet<string> Convertable = new(StringComparer.OrdinalIgnoreCase)
    {
        ".mobi", ".azw", ".azw3", ".cbz", ".cbr", ".zip", ".pdf"
    };

    public static readonly HashSet<string> Openable = new(Convertable, StringComparer.OrdinalIgnoreCase)
    {
        ".epub"
    };
}
