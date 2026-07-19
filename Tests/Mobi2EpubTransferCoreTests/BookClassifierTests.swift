import Foundation
import Testing
@testable import Mobi2EpubTransferCore

struct BookClassifierTests {
    @Test
    func comicArchiveExtensionsAreHighConfidence() async throws {
        let result = try await BookClassifier().classify(url: URL(fileURLWithPath: "/tmp/volume.cbz"))
        #expect(result.kind == .comic)
        #expect(result.confidence == 1)
    }

    @Test
    func imageDominatedZIPIsComic() async throws {
        let runner = ArchiveListingRunner(output: "cover.jpg\n001.jpg\n002.png\nnotes.txt\n")
        let result = try await BookClassifier(runner: runner).classify(url: URL(fileURLWithPath: "/tmp/book.zip"))
        #expect(result.kind == .uncertain)

        let comicRunner = ArchiveListingRunner(output: "001.jpg\n002.jpg\n003.png\n004.webp\n")
        let comic = try await BookClassifier(runner: comicRunner).classify(url: URL(fileURLWithPath: "/tmp/book.zip"))
        #expect(comic.kind == .comic)
    }

    @Test
    func epubTextThresholdsAreDeterministic() {
        #expect(BookClassifier.classifyEPUBTextCounts([240, 300, 420, 12]).kind == .text)
        #expect(BookClassifier.classifyEPUBTextCounts([220, 30, 40, 50]).kind == .uncertain)
    }

    @Test
    func pdfTextAndScanThresholdsAreDeterministic() {
        #expect(BookClassifier.classifyPDFTextCounts([500, 620, 410, 40, 700]).kind == .text)
        #expect(BookClassifier.classifyPDFTextCounts([0, 12, 20, 0, 90]).kind == .comic)
        #expect(BookClassifier.classifyPDFTextCounts([500, 10, 100, 40, 300]).kind == .uncertain)
    }
}

private actor ArchiveListingRunner: ProcessRunning {
    let output: String
    init(output: String) { self.output = output }
    func run(executableURL: URL, arguments: [String]) async throws -> ProcessRunResult {
        ProcessRunResult(exitCode: 0, output: output)
    }
    func run(executableURL: URL, arguments: [String], currentDirectoryURL: URL?) async throws -> ProcessRunResult {
        ProcessRunResult(exitCode: 0, output: output)
    }
}
