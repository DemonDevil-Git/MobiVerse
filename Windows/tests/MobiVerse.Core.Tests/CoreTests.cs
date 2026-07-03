using MobiVerse.Core;
using System.IO.Compression;
using System.Text;
using Xunit;

namespace MobiVerse.Core.Tests;

public sealed class FileOutputPolicyTests : IDisposable
{
    private readonly string _root = TestData.Directory();
    [Fact] public void UsesSourceDirectoryAndEpubExtension() { var input = TestData.File(_root, "book.mobi"); Assert.Equal(Path.Combine(_root, "book.epub"), new FileOutputPolicy().EpubOutputPath(input)); }
    [Fact] public void DoesNotOverwriteExistingOutput() { var input = TestData.File(_root, "book.cbz"); TestData.File(_root, "book.epub"); Assert.Equal(Path.Combine(_root, "book 2.epub"), new FileOutputPolicy().EpubOutputPath(input)); }
    [Fact] public void IncrementsPastMultipleOutputs() { var input = TestData.File(_root, "book.pdf"); TestData.File(_root, "book.epub"); TestData.File(_root, "book 2.epub"); Assert.EndsWith("book 3.epub", new FileOutputPolicy().EpubOutputPath(input)); }
    [Fact] public void RejectsUnsupportedInput() => Assert.Throws<ArgumentException>(() => new FileOutputPolicy().EpubOutputPath(Path.Combine(_root, "book.txt")));
    public void Dispose() => TestData.Delete(_root);
}

public sealed class FailureClassificationTests
{
    [Fact] public void FindsDrm() => Assert.Equal(ConversionFailureKind.DrmProtected, ConverterService.ClassifyFailure("Book is encrypted with DRM"));
    [Fact] public void FindsUnreadableInput() => Assert.Equal(ConversionFailureKind.InputUnreadable, ConverterService.ClassifyFailure("bad magic: corrupt"));
    [Fact] public void FindsPermissionFailure() => Assert.Equal(ConversionFailureKind.OutputPermissionDenied, ConverterService.ClassifyFailure("Access is denied"));
    [Fact] public void FallsBackToGenericFailure() => Assert.Equal(ConversionFailureKind.ConversionFailed, ConverterService.ClassifyFailure("unknown conversion crash"));
}

public sealed class PersistenceTests : IDisposable
{
    private readonly string _root = TestData.Directory();
    [Fact] public void SavesAndLoadsHistory() { var store = new HistoryStore(Path.Combine(_root, "history.json")); store.Save([new ConversionTask { InputPath = "C:\\book.mobi", Status = ConversionStatus.Succeeded }]); Assert.Single(store.Load()); }
    [Fact] public void RestoresInterruptedTaskAsFailed() { var store = new HistoryStore(Path.Combine(_root, "history.json")); store.Save([new ConversionTask { InputPath = "C:\\book.mobi", Status = ConversionStatus.Converting }]); Assert.Equal(ConversionStatus.Failed, store.Load()[0].Status); }
    [Fact] public void SavesReadingPosition() { var store = new ReadingPositionStore(Path.Combine(_root, "position.json")); store.Save("C:\\book.epub", 9); Assert.Equal(9, store.Get("C:\\book.epub")); }
    [Fact] public void ClampsNegativeReadingPosition() { var store = new ReadingPositionStore(Path.Combine(_root, "position.json")); store.Save("C:\\book.epub", -8); Assert.Equal(0, store.Get("C:\\book.epub")); }
    public void Dispose() => TestData.Delete(_root);
}

public sealed class PathSecurityTests : IDisposable
{
    private readonly string _root = TestData.Directory();
    [Fact] public void AcceptsContainedPath() => Assert.NotNull(EpubPathSecurity.Resolve("images/page.jpg", _root, _root));
    [Fact] public void RejectsParentTraversal() => Assert.Null(EpubPathSecurity.Resolve("../secret.txt", _root, _root));
    [Fact] public void RejectsEncodedParentTraversal() => Assert.Null(EpubPathSecurity.Resolve("%2e%2e/secret.txt", _root, _root));
    [Fact] public void RejectsAbsoluteUri() => Assert.Null(EpubPathSecurity.Resolve("https://example.com/page.jpg", _root, _root));
    [Fact] public void RejectsZipSlipEntry() { var archive = Path.Combine(_root, "bad.epub"); using (var zip = ZipFile.Open(archive, ZipArchiveMode.Create)) { var entry = zip.CreateEntry("../escape.txt"); using var writer = new StreamWriter(entry.Open()); writer.Write("bad"); } Assert.Throws<InvalidDataException>(() => EpubPathSecurity.ExtractSafely(archive, Path.Combine(_root, "out"))); }
    public void Dispose() => TestData.Delete(_root);
}

public sealed class ToolAndValidatorTests : IDisposable
{
    private readonly string _root = TestData.Directory();
    [Fact] public void BundledCalibreTakesPrecedence() { var calibre = Directory.CreateDirectory(Path.Combine(_root, "ThirdParty", "calibre")).FullName; TestData.File(calibre, "ebook-convert.exe"); TestData.File(calibre, "ebook-meta.exe"); var tools = new ToolchainLocator(_root).Inspect(); Assert.True(tools.HasCalibre); Assert.True(tools.IsBundled); }
    [Fact] public async Task ValidationSkipsWhenToolIsMissing() { var report = Path.Combine(_root, "report.txt"); var result = await new EpubValidator(new FakeRunner(), null).ValidateAsync("book.epub", report, "", "post"); Assert.Equal(EpubValidationStatus.Skipped, result.Status); }
    [Fact] public async Task ValidationPassesWithoutWarnings() { var report = Path.Combine(_root, "report.txt"); var result = await new EpubValidator(new FakeRunner(new(0, "No errors")), "epubcheck.exe").ValidateAsync("book.epub", report, "", "post"); Assert.Equal(EpubValidationStatus.Passed, result.Status); }
    [Fact] public async Task ValidationReportsWarnings() { var report = Path.Combine(_root, "report.txt"); var result = await new EpubValidator(new FakeRunner(new(0, "WARNING one")), "epubcheck.exe").ValidateAsync("book.epub", report, "", "post"); Assert.Equal(EpubValidationStatus.Warnings, result.Status); }
    public void Dispose() => TestData.Delete(_root);
}

public sealed class ConverterTests : IDisposable
{
    private readonly string _root = TestData.Directory();
    [Fact] public async Task PdfUsesNativeRendererWithoutCalibre() { var input = TestData.File(_root, "book.pdf"); var output = Path.Combine(_root, "book.epub"); var service = new ConverterService(new FakeRunner(), new FakeLocator(new(null, null, null, false)), new FakePdfRenderer(), new EpubArchiveService()); var result = await service.ConvertAsync(input, output); Assert.Equal(ConversionStrategy.NativePdfFixedLayout, result.Strategy); Assert.True(File.Exists(output)); }
    [Fact] public async Task MissingCalibreFailsNonPdf() { var input = TestData.File(_root, "book.mobi"); var service = new ConverterService(new FakeRunner(), new FakeLocator(new(null, null, null, false)), new FakePdfRenderer(), new EpubArchiveService()); var error = await Assert.ThrowsAsync<ConversionException>(() => service.ConvertAsync(input, Path.Combine(_root, "book.epub"))); Assert.Equal(ConversionFailureKind.MissingCalibre, error.Kind); }
    public void Dispose() => TestData.Delete(_root);
}

public sealed class ArchiveTests : IDisposable
{
    private readonly string _root = TestData.Directory();
    [Fact] public void MimetypeIsFirstAndStored() { var epub = Build(); using var archive = ZipFile.OpenRead(epub); Assert.Equal("mimetype", archive.Entries[0].FullName); Assert.Equal(archive.Entries[0].Length, archive.Entries[0].CompressedLength); }
    [Fact] public void WritesFixedLayoutAndRtlMetadata() { var epub = Build(); var extraction = Path.Combine(_root, "extract"); EpubPathSecurity.ExtractSafely(epub, extraction); var opf = File.ReadAllText(Path.Combine(extraction, "OEBPS", "content.opf")); Assert.Contains("pre-paginated", opf); Assert.Contains("page-progression-direction=\"rtl\"", opf); }
    [Fact] public void NeverLeavesReplacementArchive() { var epub = Build(); Assert.Empty(Directory.EnumerateFiles(_root, ".*-*.epub")); Assert.True(File.Exists(epub)); }
    private string Build() { var first = TestData.Png(_root, "01.png", 100, 200); var second = TestData.Png(_root, "02.png", 100, 200); var epub = Path.Combine(_root, "book.epub"); new EpubArchiveService().BuildFixedLayout("Book", [first, second], epub); return epub; }
    public void Dispose() => TestData.Delete(_root);
}

public sealed class PreviewParserTests : IDisposable
{
    private readonly string _root = TestData.Directory();
    [Fact] public void ParsesImageEpubAsPages() { var epub = TestData.FixedLayoutEpub(_root); var book = new EpubPreviewParser().Parse(epub, Path.Combine(_root, "image-extract")); Assert.Equal(EpubPreviewKind.ImagePages, book.Kind); Assert.Equal(2, book.ImagePages.Count); }
    [Fact] public void ParsesTextEpubAsWeb() { var epub = TestData.TextEpub(_root); var book = new EpubPreviewParser().Parse(epub, Path.Combine(_root, "text-extract")); Assert.Equal(EpubPreviewKind.Web, book.Kind); Assert.NotNull(book.StartDocumentPath); }
    [Fact] public void ExtractsManifestCover() { var epub = TestData.FixedLayoutEpub(_root); var cover = new EpubPreviewParser().ExtractCover(epub, Path.Combine(_root, "cover-extract")); Assert.NotNull(cover); Assert.True(File.Exists(cover)); }
    public void Dispose() => TestData.Delete(_root);
}

internal sealed class FakeRunner(ProcessRunResult? result = null) : IProcessRunner
{
    public Task<ProcessRunResult> RunAsync(string executablePath, IReadOnlyList<string> arguments, string? workingDirectory = null, CancellationToken cancellationToken = default) => Task.FromResult(result ?? new ProcessRunResult(0, ""));
}

internal sealed class FakeLocator(ToolchainAvailability availability) : IToolchainLocator { public ToolchainAvailability Inspect() => availability; }

internal sealed class FakePdfRenderer : IPdfPageRenderer
{
    public Task<PdfRenderResult> RenderAsync(string inputPath, string outputDirectory, IProgress<ConversionProgressUpdate>? progress, CancellationToken cancellationToken)
    {
        var first = TestData.Png(outputDirectory, "01.png", 100, 200); var second = TestData.Png(outputDirectory, "02.png", 100, 200);
        return Task.FromResult(new PdfRenderResult("PDF", [first, second]));
    }
}

internal static class TestData
{
    public static string Directory() { var path = Path.Combine(Path.GetTempPath(), "MobiVerseTests", Guid.NewGuid().ToString("N")); System.IO.Directory.CreateDirectory(path); return path; }
    public static string File(string directory, string name) { System.IO.Directory.CreateDirectory(directory); var path = Path.Combine(directory, name); System.IO.File.WriteAllText(path, "test"); return path; }
    public static string Png(string directory, string name, int width, int height) { System.IO.Directory.CreateDirectory(directory); var bytes = new byte[24]; new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }.CopyTo(bytes, 0); WriteBigEndian(bytes, 16, width); WriteBigEndian(bytes, 20, height); var path = Path.Combine(directory, name); System.IO.File.WriteAllBytes(path, bytes); return path; }
    public static string FixedLayoutEpub(string root) { var image1 = Png(root, "a.png", 100, 200); var image2 = Png(root, "b.png", 100, 200); var output = Path.Combine(root, $"fixed-{Guid.NewGuid():N}.epub"); new EpubArchiveService().BuildFixedLayout("Comic", [image1, image2], output); return output; }
    public static string TextEpub(string root)
    {
        var output = Path.Combine(root, $"text-{Guid.NewGuid():N}.epub");
        using var archive = ZipFile.Open(output, ZipArchiveMode.Create);
        Add(archive, "META-INF/container.xml", "<container xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\"><rootfiles><rootfile full-path=\"OEBPS/content.opf\"/></rootfiles></container>");
        Add(archive, "OEBPS/content.opf", "<package xmlns=\"http://www.idpf.org/2007/opf\"><metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:title>Text</dc:title></metadata><manifest><item id=\"page\" href=\"page.xhtml\" media-type=\"application/xhtml+xml\"/></manifest><spine><itemref idref=\"page\"/></spine></package>");
        Add(archive, "OEBPS/page.xhtml", "<html xmlns=\"http://www.w3.org/1999/xhtml\"><body>Text</body></html>");
        return output;
    }
    public static void Delete(string root) { try { System.IO.Directory.Delete(root, true); } catch { } }
    private static void Add(ZipArchive archive, string path, string text) { var entry = archive.CreateEntry(path); using var writer = new StreamWriter(entry.Open(), new UTF8Encoding(false)); writer.Write(text); }
    private static void WriteBigEndian(byte[] bytes, int offset, int value) { bytes[offset] = (byte)(value >> 24); bytes[offset + 1] = (byte)(value >> 16); bytes[offset + 2] = (byte)(value >> 8); bytes[offset + 3] = (byte)value; }
}
