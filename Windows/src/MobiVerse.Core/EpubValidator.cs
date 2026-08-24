namespace MobiVerse.Core;

public sealed class EpubValidator(IProcessRunner runner, string? epubCheckPath)
{
    public async Task<(EpubValidationStatus Status, string ReportPath)> ValidateAsync(
        string epubPath,
        string reportPath,
        string conversionLog,
        string postProcessReport,
        CancellationToken cancellationToken = default)
    {
        EpubValidationStatus status;
        string body;
        if (epubCheckPath is null)
        {
            status = EpubValidationStatus.Skipped;
            body = "EPUBCheck was not found. The EPUB was created, but structural validation was not performed.";
        }
        else
        {
            var result = await runner.RunAsync(epubCheckPath, [epubPath], cancellationToken: cancellationToken).ConfigureAwait(false);
            status = ValidationStatus(result.ExitCode, result.Output);
            body = string.IsNullOrWhiteSpace(result.Output) ? "EPUBCheck completed without output." : result.Output;
        }
        var report = $"""
EPUBCheck {status.ToString().ToLowerInvariant()}

Validation
----------
{body}

{postProcessReport}

Calibre conversion log
----------------------
{(string.IsNullOrWhiteSpace(conversionLog) ? "No Calibre log output." : conversionLog)}
""";
        await File.WriteAllTextAsync(reportPath, report, cancellationToken).ConfigureAwait(false);
        return (status, reportPath);
    }

    public static EpubValidationStatus ValidationStatus(int exitCode, string output)
    {
        if (exitCode != 0) return EpubValidationStatus.Failed;
        if (output.Contains("no errors or warnings detected", StringComparison.OrdinalIgnoreCase) ||
            output.Contains("0 errors / 0 warnings", StringComparison.OrdinalIgnoreCase)) return EpubValidationStatus.Passed;
        return output.Contains("warning", StringComparison.OrdinalIgnoreCase) || output.Contains("warn", StringComparison.OrdinalIgnoreCase)
            ? EpubValidationStatus.Warnings
            : EpubValidationStatus.Passed;
    }
}
