namespace MobiVerse.Core;

public sealed class ConverterService(
    IProcessRunner runner,
    IToolchainLocator locator,
    IPdfPageRenderer pdfRenderer,
    EpubArchiveService archiveService) : IConverterService
{
    public async Task<ConversionRunResult> ConvertAsync(
        string inputPath,
        string outputPath,
        IProgress<ConversionProgressUpdate>? progress = null,
        CancellationToken cancellationToken = default,
        ConversionProfile profile = ConversionProfile.ComicFixedLayout,
        EpubReadingDirection readingDirection = EpubReadingDirection.RightToLeft)
    {
        if (Path.GetExtension(inputPath).Equals(".pdf", StringComparison.OrdinalIgnoreCase) &&
            profile == ConversionProfile.ComicFixedLayout)
        {
            var workingDirectory = Path.Combine(Path.GetTempPath(), "MobiVersePDFConversion", Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(workingDirectory);
            try
            {
                var rendered = await pdfRenderer.RenderAsync(inputPath, workingDirectory, progress, cancellationToken).ConfigureAwait(false);
                progress?.Report(new(.92, $"Packaging {rendered.ImagePaths.Count} pages into EPUB", rendered.ImagePaths.Count, rendered.ImagePaths.Count));
                var report = archiveService.BuildFixedLayout(rendered.Title, rendered.ImagePaths, outputPath, readingDirection);
                progress?.Report(new(1, "PDF conversion complete", rendered.ImagePaths.Count, rendered.ImagePaths.Count));
                return new(outputPath, $"Native PDF conversion\n---------------------\nRenderer: Windows.Data.Pdf\nPages: {rendered.ImagePaths.Count}\nMaximum image edge: 2200 px\nJPEG quality: 0.86\nCalibre PDF reflow: skipped", ConversionStrategy.NativePdfFixedLayout, report);
            }
            finally { try { Directory.Delete(workingDirectory, true); } catch { } }
        }

        var tools = locator.Inspect();
        if (!tools.HasCalibre)
            throw new ConversionException(ConversionFailureKind.MissingCalibre, "Calibre CLI was not found. Reinstall MobiVerse or install Calibre.");

        var preparedInput = inputPath;
        string? temporaryDirectory = null;
        if (Path.GetExtension(inputPath).Equals(".zip", StringComparison.OrdinalIgnoreCase))
        {
            temporaryDirectory = Path.Combine(Path.GetTempPath(), "MobiVerseZIPComicInput", Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(temporaryDirectory);
            preparedInput = Path.Combine(temporaryDirectory, Path.GetFileNameWithoutExtension(inputPath) + ".cbz");
            File.Copy(inputPath, preparedInput);
        }

        try
        {
            progress?.Report(new(.08, "Converting with Calibre", 0, 1));
            var arguments = new List<string>
            {
                preparedInput, outputPath, "--preserve-cover-aspect-ratio", "--disable-font-rescaling", "--pretty-print"
            };
            if (profile == ConversionProfile.TextReflow)
            {
                arguments.Add("--epub-version=3");
            }
            else
            {
                arguments.AddRange([
                    "--epub-max-image-size=none", "--margin-top=0", "--margin-right=0", "--margin-bottom=0", "--margin-left=0",
                    "--filter-css=height,width,margin,margin-left,margin-right,margin-top,margin-bottom,padding,padding-left,padding-right,padding-top,padding-bottom",
                    $"--extra-css={ComicExtraCss}"
                ]);
            }
            var result = await runner.RunAsync(tools.EbookConvertPath!, arguments, cancellationToken: cancellationToken).ConfigureAwait(false);
            if (result.ExitCode != 0)
            {
                var kind = ClassifyFailure(result.Output);
                throw new ConversionException(kind, Message(kind), result.Output);
            }
            progress?.Report(new(.65, profile == ConversionProfile.TextReflow ? "Repairing text EPUB structure" : "Optimizing comic EPUB layout", 1, 1));
            var report = profile == ConversionProfile.TextReflow
                ? new TextEpubPostProcessor().Process(outputPath).ReportText
                : archiveService.ProcessComicEpub(outputPath, readingDirection);
            return new(outputPath, result.Output, ConversionStrategy.Calibre, report);
        }
        finally
        {
            if (temporaryDirectory is not null) try { Directory.Delete(temporaryDirectory, true); } catch { }
        }
    }

    public static ConversionFailureKind ClassifyFailure(string log)
    {
        var value = log.ToLowerInvariant();
        if (new[] { "drm", "encrypted", "this book is locked", "protected by" }.Any(value.Contains)) return ConversionFailureKind.DrmProtected;
        if (new[] { "no such file", "not a valid", "could not open", "bad magic", "corrupt", "truncated", "unknown format", "unsupported format", "no suitable input plugin", "not a rar file", "unrar" }.Any(value.Contains)) return ConversionFailureKind.InputUnreadable;
        if (new[] { "permission denied", "access is denied", "read-only file system" }.Any(value.Contains)) return ConversionFailureKind.OutputPermissionDenied;
        return ConversionFailureKind.ConversionFailed;
    }

    public static string Message(ConversionFailureKind kind) => kind switch
    {
        ConversionFailureKind.MissingCalibre => "Calibre CLI was not found. Reinstall MobiVerse or install Calibre.",
        ConversionFailureKind.DrmProtected => "This file appears to be protected. MobiVerse does not remove DRM.",
        ConversionFailureKind.InputUnreadable => "The source file could not be read or appears to be damaged.",
        ConversionFailureKind.OutputPermissionDenied => "The app could not write the EPUB in the source folder. Check folder permissions.",
        _ => "Calibre could not convert this file. Review the conversion log for details."
    };

    public const string ComicExtraCss = "html,body{margin:0!important;padding:0!important;width:100%!important;height:100%!important;background:#000!important}body.calibre,.calibre,.calibre1{display:block!important;margin:0!important;padding:0!important;text-align:center!important;text-indent:0!important;line-height:0!important}img,.calibre2{display:block!important;width:auto!important;height:auto!important;max-width:100%!important;max-height:100vh!important;margin:0 auto!important;object-fit:contain!important;page-break-inside:avoid!important}@page{margin:0!important;padding:0!important}";
}
