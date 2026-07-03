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
    string? StartDocumentPath);

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
