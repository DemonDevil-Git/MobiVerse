import Foundation

public enum ConversionFailureKind: Equatable, Sendable {
    case missingCalibre
    case drmProtected
    case inputUnreadable
    case outputPermissionDenied
    case conversionFailed
}

public struct ConversionServiceError: Error, Equatable {
    public let kind: ConversionFailureKind
    public let message: String
    public let log: String

    public init(kind: ConversionFailureKind, message: String, log: String = "") {
        self.kind = kind
        self.message = message
        self.log = log
    }
}

public struct ConversionRunResult: Equatable, Sendable {
    public let outputURL: URL
    public let log: String
    public let strategy: ConversionStrategy
    public let postProcessReport: String?

    public init(
        outputURL: URL,
        log: String,
        strategy: ConversionStrategy = .calibre,
        postProcessReport: String? = nil
    ) {
        self.outputURL = outputURL
        self.log = log
        self.strategy = strategy
        self.postProcessReport = postProcessReport
    }
}

public enum ConversionStrategy: Equatable, Sendable {
    case calibre
    case nativePDFFixedLayout
}

public struct ConversionProgressUpdate: Equatable, Sendable {
    public let fraction: Double
    public let message: String
    public let completedUnitCount: Int
    public let totalUnitCount: Int

    public init(
        fraction: Double,
        message: String,
        completedUnitCount: Int,
        totalUnitCount: Int
    ) {
        self.fraction = fraction
        self.message = message
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
    }
}

public typealias ConversionProgressHandler = @Sendable (ConversionProgressUpdate) -> Void

public struct ConverterService: Sendable {
    private let ebookConvertURL: URL?
    private let runner: any ProcessRunning

    public init(ebookConvertURL: URL?, runner: any ProcessRunning = ProcessRunner()) {
        self.ebookConvertURL = ebookConvertURL
        self.runner = runner
    }

    public func convert(
        inputURL: URL,
        outputURL: URL,
        profile: ConversionProfile = .comicFixedLayout,
        readingDirection: EpubReadingDirection = .rightToLeft,
        progressHandler: ConversionProgressHandler? = nil
    ) async throws -> ConversionRunResult {
        if inputURL.pathExtension.lowercased() == "pdf", profile == .comicFixedLayout {
            return try await PDFEpubConverter(runner: runner).convert(
                inputURL: inputURL,
                outputURL: outputURL,
                readingDirection: readingDirection,
                progressHandler: progressHandler
            )
        }

        guard let ebookConvertURL else {
            throw ConversionServiceError(
                kind: .missingCalibre,
                message: "Calibre CLI was not found. Install Calibre before converting."
            )
        }

        let preparedInput = try prepareInputForCalibre(inputURL)
        defer {
            preparedInput.cleanup()
        }

        var arguments = [
            preparedInput.url.path,
            outputURL.path,
            "--preserve-cover-aspect-ratio",
            "--disable-font-rescaling",
            "--pretty-print"
        ]
        if profile == .textReflow {
            // EPUB 3 preserves semantic HTML such as Japanese ruby annotations.
            // Calibre's EPUB 2 output rejects <ruby> during EPUBCheck validation.
            arguments.append("--epub-version=3")
        } else {
            arguments += [
            "--epub-max-image-size=none",
            "--margin-top=0",
            "--margin-right=0",
            "--margin-bottom=0",
            "--margin-left=0",
            "--filter-css=height,width,margin,margin-left,margin-right,margin-top,margin-bottom,padding,padding-left,padding-right,padding-top,padding-bottom",
            "--extra-css=\(Self.comicExtraCSS)"
            ]
        }

        let result = try await runner.run(executableURL: ebookConvertURL, arguments: arguments)
        guard result.exitCode == 0 else {
            let kind = Self.classifyFailure(log: result.output)
            throw ConversionServiceError(
                kind: kind,
                message: Self.message(for: kind),
                log: result.output
            )
        }

        return ConversionRunResult(outputURL: outputURL, log: result.output)
    }

    private func prepareInputForCalibre(_ inputURL: URL) throws -> PreparedInput {
        guard SupportedInputFormat.format(for: inputURL)?.isZipComicArchive == true else {
            return PreparedInput(url: inputURL)
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MobiVerseZIPComicInput", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let cbzURL = temporaryDirectory
            .appendingPathComponent(inputURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("cbz")
        try FileManager.default.copyItem(at: inputURL, to: cbzURL)
        return PreparedInput(url: cbzURL, cleanupURL: temporaryDirectory)
    }

    public static func classifyFailure(log: String) -> ConversionFailureKind {
        let lowercasedLog = log.lowercased()
        let drmMarkers = [
            "drm",
            "encrypted",
            "this book is locked",
            "cannot be converted because it is protected",
            "protected by"
        ]
        if drmMarkers.contains(where: { lowercasedLog.contains($0) }) {
            return .drmProtected
        }

        let inputMarkers = [
            "no such file",
            "not a valid",
            "could not open",
            "bad magic",
            "corrupt",
            "truncated",
            "unknown format",
            "unsupported format",
            "no suitable input plugin",
            "not a rar file",
            "unrar"
        ]
        if inputMarkers.contains(where: { lowercasedLog.contains($0) }) {
            return .inputUnreadable
        }

        let permissionMarkers = [
            "permission denied",
            "operation not permitted",
            "read-only file system"
        ]
        if permissionMarkers.contains(where: { lowercasedLog.contains($0) }) {
            return .outputPermissionDenied
        }

        return .conversionFailed
    }

    public static let comicExtraCSS = """
    html, body {
      margin: 0 !important;
      padding: 0 !important;
      width: 100% !important;
      height: 100% !important;
      background: #000 !important;
    }
    body.calibre, .calibre, .calibre1 {
      display: block !important;
      margin: 0 !important;
      padding: 0 !important;
      text-align: center !important;
      text-indent: 0 !important;
      line-height: 0 !important;
    }
    img, .calibre2 {
      display: block !important;
      width: auto !important;
      height: auto !important;
      max-width: 100% !important;
      max-height: 100vh !important;
      margin: 0 auto !important;
      object-fit: contain !important;
      page-break-inside: avoid !important;
    }
    @page {
      margin: 0 !important;
      padding: 0 !important;
    }
    """

    public static func message(for kind: ConversionFailureKind) -> String {
        switch kind {
        case .missingCalibre:
            "Calibre CLI was not found. Install Calibre before converting."
        case .drmProtected:
            "This file appears to be protected. MobiVerse does not remove DRM."
        case .inputUnreadable:
            "The source file could not be read or appears to be damaged."
        case .outputPermissionDenied:
            "The app could not write the EPUB in the source folder. Check folder permissions."
        case .conversionFailed:
            "Calibre could not convert this file. Review the conversion log for details."
        }
    }
}

private struct PreparedInput {
    let url: URL
    let cleanupURL: URL?

    init(url: URL, cleanupURL: URL? = nil) {
        self.url = url
        self.cleanupURL = cleanupURL
    }

    func cleanup() {
        guard let cleanupURL else { return }
        try? FileManager.default.removeItem(at: cleanupURL)
    }
}
