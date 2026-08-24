namespace MobiVerse.Core;

public interface IProcessRunner
{
    Task<ProcessRunResult> RunAsync(
        string executablePath,
        IReadOnlyList<string> arguments,
        string? workingDirectory = null,
        CancellationToken cancellationToken = default);
}

public interface IToolchainLocator
{
    ToolchainAvailability Inspect();
}

public interface IPdfPageRenderer
{
    Task<PdfRenderResult> RenderAsync(
        string inputPath,
        string outputDirectory,
        IProgress<ConversionProgressUpdate>? progress,
        CancellationToken cancellationToken);
}

public sealed record PdfRenderResult(string Title, IReadOnlyList<string> ImagePaths);

public interface IConverterService
{
    Task<ConversionRunResult> ConvertAsync(
        string inputPath,
        string outputPath,
        IProgress<ConversionProgressUpdate>? progress = null,
        CancellationToken cancellationToken = default,
        ConversionProfile profile = ConversionProfile.ComicFixedLayout,
        EpubReadingDirection readingDirection = EpubReadingDirection.RightToLeft);
}

public interface IHistoryStore
{
    IReadOnlyList<ConversionTask> Load();
    void Save(IReadOnlyList<ConversionTask> tasks);
}
