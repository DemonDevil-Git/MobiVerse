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
            status = result.ExitCode != 0
                ? EpubValidationStatus.Failed
                : result.Output.Contains("warn", StringComparison.OrdinalIgnoreCase)
                    ? EpubValidationStatus.Warnings
                    : EpubValidationStatus.Passed;
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
}
