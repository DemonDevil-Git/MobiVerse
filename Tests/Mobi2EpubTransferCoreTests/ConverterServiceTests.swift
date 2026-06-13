import Foundation
import Testing
@testable import Mobi2EpubTransferCore

struct ConverterServiceTests {
    @Test
    func comicConversionCSSRemovesMarginsAndFixedImageSizing() {
        #expect(ConverterService.comicExtraCSS.contains("margin: 0 !important"))
        #expect(ConverterService.comicExtraCSS.contains("max-width: 100% !important"))
        #expect(ConverterService.comicExtraCSS.contains("max-height: 100vh !important"))
        #expect(ConverterService.comicExtraCSS.contains("@page"))
    }

    @Test
    func zipComicInputIsPresentedToCalibreAsCBZ() async throws {
        let directory = try TemporaryDirectory()
        let inputURL = directory.url.appendingPathComponent("Comic.zip")
        let outputURL = directory.url.appendingPathComponent("Comic.epub")
        FileManager.default.createFile(atPath: inputURL.path, contents: Data([1, 2, 3]))
        let runner = RecordingRunner()
        let service = ConverterService(
            ebookConvertURL: URL(fileURLWithPath: "/tmp/ebook-convert"),
            runner: runner
        )

        _ = try await service.convert(inputURL: inputURL, outputURL: outputURL)

        let arguments = await runner.recordedArguments
        #expect(arguments.first?.hasSuffix(".cbz") == true)
        #expect(arguments.dropFirst().first == outputURL.path)
    }
}

private actor RecordingRunner: ProcessRunning {
    private(set) var recordedArguments: [String] = []

    func run(executableURL: URL, arguments: [String]) async throws -> ProcessRunResult {
        recordedArguments = arguments
        return ProcessRunResult(exitCode: 0, output: "ok")
    }

    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?
    ) async throws -> ProcessRunResult {
        recordedArguments = arguments
        return ProcessRunResult(exitCode: 0, output: "ok")
    }
}
