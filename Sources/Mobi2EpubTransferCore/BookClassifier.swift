import Foundation
import PDFKit

public enum BookClassifierError: Error, Equatable, Sendable {
    case unsupportedFormat
    case unreadableArchive
    case missingCalibre
}

public struct BookClassifier {
    private let ebookConvertURL: URL?
    private let runner: any ProcessRunning
    private let fileManager: FileManager

    public init(
        ebookConvertURL: URL? = nil,
        runner: any ProcessRunning = ProcessRunner(),
        fileManager: FileManager = .default
    ) {
        self.ebookConvertURL = ebookConvertURL
        self.runner = runner
        self.fileManager = fileManager
    }

    public func classify(url: URL) async throws -> ClassificationResult {
        switch url.pathExtension.lowercased() {
        case "cbz", "cbr":
            return ClassificationResult(kind: .comic, confidence: 1, evidence: "Comic archive format")
        case "zip":
            return try await classifyZIP(url)
        case "epub":
            return try await classifyEPUB(url)
        case "pdf":
            return try classifyPDF(url)
        case "mobi", "azw", "azw3":
            return try await classifyCalibreBook(url)
        default:
            throw BookClassifierError.unsupportedFormat
        }
    }

    private func classifyZIP(_ url: URL) async throws -> ClassificationResult {
        let result = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-Z1", url.path]
        )
        guard result.exitCode == 0 else { throw BookClassifierError.unreadableArchive }
        let entries = result.output.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.hasSuffix("/") }
        guard !entries.isEmpty else { throw BookClassifierError.unreadableArchive }
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "avif"]
        let imageCount = entries.filter { imageExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }.count
        let ratio = Double(imageCount) / Double(entries.count)
        if imageCount >= 2, ratio >= 0.8 {
            return ClassificationResult(kind: .comic, confidence: min(1, ratio), evidence: "\(imageCount) of \(entries.count) archive files are images")
        }
        return ClassificationResult(kind: .uncertain, confidence: 0.35, evidence: "Archive is not predominantly image pages")
    }

    private func classifyEPUB(_ url: URL) async throws -> ClassificationResult {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("MobiVerseClassification", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }
        let book = try await EpubPreviewParser(runner: runner, fileManager: fileManager).parse(
            epubURL: url,
            extractionDirectory: directory
        )
        switch book.mode {
        case .imagePages(let pages):
            return ClassificationResult(kind: .comic, confidence: 0.95, evidence: "\(pages.count) spine items are full-page images")
        case .web(let spineURLs):
            let counts = spineURLs.map(visibleCharacterCount)
            return Self.classifyEPUBTextCounts(counts)
        }
    }

    private func classifyPDF(_ url: URL) throws -> ClassificationResult {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw BookClassifierError.unreadableArchive
        }
        let sampleCount = min(20, document.pageCount)
        let indices = sampleIndices(total: document.pageCount, count: sampleCount)
        let counts = indices.map { index in
            document.page(at: index)?.string?.filter { !$0.isWhitespace }.count ?? 0
        }
        return Self.classifyPDFTextCounts(counts)
    }

    static func classifyEPUBTextCounts(_ counts: [Int]) -> ClassificationResult {
        let textPages = counts.filter { $0 >= 200 }.count
        let ratio = counts.isEmpty ? 0 : Double(textPages) / Double(counts.count)
        let median = medianValue(counts)
        if ratio >= 0.6, median >= 200 {
            return ClassificationResult(kind: .text, confidence: min(0.98, 0.7 + ratio * 0.25), evidence: "\(textPages) of \(counts.count) spine sections contain substantial text")
        }
        return ClassificationResult(kind: .uncertain, confidence: 0.45, evidence: "The book mixes image pages and short text sections")
    }

    static func classifyPDFTextCounts(_ counts: [Int]) -> ClassificationResult {
        guard !counts.isEmpty else {
            return ClassificationResult(kind: .uncertain, confidence: 0, evidence: "PDF contains no readable pages")
        }
        let richPages = counts.filter { $0 >= 200 }.count
        let readablePages = counts.filter { $0 >= 80 }.count
        let richRatio = Double(richPages) / Double(counts.count)
        let readableRatio = Double(readablePages) / Double(counts.count)
        if richRatio >= 0.6, medianValue(counts) >= 400 {
            return ClassificationResult(kind: .text, confidence: min(0.96, 0.72 + richRatio * 0.24), evidence: "Most sampled PDF pages contain selectable text")
        }
        if readableRatio <= 0.2 {
            return ClassificationResult(kind: .comic, confidence: 0.9, evidence: "PDF pages are predominantly images or scans")
        }
        return ClassificationResult(kind: .uncertain, confidence: 0.45, evidence: "PDF contains a mixture of text and image-heavy pages")
    }

    private func classifyCalibreBook(_ url: URL) async throws -> ClassificationResult {
        guard ebookConvertURL != nil else { throw BookClassifierError.missingCalibre }
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("MobiVerseNeutralClassification", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        let epubURL = directory.appendingPathComponent("neutral.epub")
        _ = try await ConverterService(ebookConvertURL: ebookConvertURL, runner: runner).convert(
            inputURL: url,
            outputURL: epubURL,
            profile: .textReflow
        )
        return try await classifyEPUB(epubURL)
    }

    private func visibleCharacterCount(at url: URL) -> Int {
        guard var text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        text = text.replacingOccurrences(of: #"<script\b[^>]*>[\s\S]*?</script>"#, with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<style\b[^>]*>[\s\S]*?</style>"#, with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return text.filter { !$0.isWhitespace }.count
    }

    private static func medianValue(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private func medianValue(_ values: [Int]) -> Int { Self.medianValue(values) }

    private func sampleIndices(total: Int, count: Int) -> [Int] {
        guard count > 1 else { return [0] }
        return (0..<count).map { Int((Double($0) * Double(total - 1) / Double(count - 1)).rounded()) }
    }
}
