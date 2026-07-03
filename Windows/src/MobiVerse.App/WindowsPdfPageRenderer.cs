using MobiVerse.Core;
using Windows.Data.Pdf;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;

namespace MobiVerse.App;

public sealed class WindowsPdfPageRenderer : IPdfPageRenderer
{
    private const int MaximumImageLongEdge = 2200;

    public async Task<PdfRenderResult> RenderAsync(
        string inputPath,
        string outputDirectory,
        IProgress<ConversionProgressUpdate>? progress,
        CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(outputDirectory);
        PdfDocument document;
        try
        {
            var file = await StorageFile.GetFileFromPathAsync(Path.GetFullPath(inputPath));
            document = await PdfDocument.LoadFromFileAsync(file);
        }
        catch (Exception exception)
        {
            throw new ConversionException(ConversionFailureKind.InputUnreadable, "The PDF could not be opened or is password protected.", exception.Message);
        }
        // PdfDocument is a WinRT object rather than IDisposable. Page and stream
        // resources are released per iteration to keep large books memory-bounded.
        {
            if (document.PageCount == 0) throw new ConversionException(ConversionFailureKind.InputUnreadable, "The PDF contains no pages.");

            var images = new List<string>((int)document.PageCount);
            for (uint index = 0; index < document.PageCount; index++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                using var page = document.GetPage(index);
                var bounds = page.Dimensions.CropBox;
                var scale = Math.Min(1d, MaximumImageLongEdge / Math.Max(bounds.Width, bounds.Height));
                var width = (uint)Math.Max(1, Math.Round(bounds.Width * scale));
                var height = (uint)Math.Max(1, Math.Round(bounds.Height * scale));
                using var renderedPng = new InMemoryRandomAccessStream();
                await page.RenderToStreamAsync(renderedPng, new PdfPageRenderOptions { DestinationWidth = width, DestinationHeight = height });
                cancellationToken.ThrowIfCancellationRequested();

                var imagePath = Path.Combine(outputDirectory, $"page-{index + 1:00000}.jpg");
                await TranscodeToJpegAsync(renderedPng, imagePath, cancellationToken);
                images.Add(imagePath);
                var completed = (int)index + 1;
                progress?.Report(new(.04 + completed / (double)document.PageCount * .84, $"Rendering PDF page {completed} of {document.PageCount}", completed, (int)document.PageCount));
            }
            return new(Path.GetFileNameWithoutExtension(inputPath), images);
        }
    }

    private static async Task TranscodeToJpegAsync(
        IRandomAccessStream source,
        string outputPath,
        CancellationToken cancellationToken)
    {
        source.Seek(0);
        var decoder = await BitmapDecoder.CreateAsync(source);
        using var bitmap = await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore);
        var outputFolder = await StorageFolder.GetFolderFromPathAsync(Path.GetDirectoryName(outputPath)!);
        var outputFile = await outputFolder.CreateFileAsync(Path.GetFileName(outputPath), CreationCollisionOption.ReplaceExisting);
        using var output = await outputFile.OpenAsync(FileAccessMode.ReadWrite);
        output.Size = 0;
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.JpegEncoderId, output);
        encoder.SetSoftwareBitmap(bitmap);
        encoder.BitmapTransform.InterpolationMode = BitmapInterpolationMode.Fant;
        encoder.IsThumbnailGenerated = false;
        var quality = new BitmapPropertySet
        {
            ["ImageQuality"] = new BitmapTypedValue(0.86, Windows.Foundation.PropertyType.Single)
        };
        await encoder.BitmapProperties.SetPropertiesAsync(quality);
        cancellationToken.ThrowIfCancellationRequested();
        await encoder.FlushAsync();
    }
}
