import Foundation

public enum EpubValidationStatus: Equatable, Sendable {
    case passed
    case warnings
    case failed
    case skipped
}

public struct EpubValidationResult: Equatable, Sendable {
    public let status: EpubValidationStatus
    public let reportURL: URL
    public let reportText: String

    public init(status: EpubValidationStatus, reportURL: URL, reportText: String) {
        self.status = status
        self.reportURL = reportURL
        self.reportText = reportText
    }
}

public struct EpubValidator: Sendable {
    private let epubCheckURL: URL?
    private let runner: any ProcessRunning

    public init(epubCheckURL: URL?, runner: any ProcessRunning = ProcessRunner()) {
        self.epubCheckURL = epubCheckURL
        self.runner = runner
    }

    public func validate(
        epubURL: URL,
        reportURL: URL,
        conversionLog: String,
        postProcessReport: String = ""
    ) async throws -> EpubValidationResult {
        guard let epubCheckURL else {
            let report = Self.report(
                title: "EPUBCheck skipped",
                body: "EPUBCheck was not found in PATH. The EPUB was created, but structural validation was not performed.",
                conversionLog: conversionLog,
                postProcessReport: postProcessReport
            )
            try report.write(to: reportURL, atomically: true, encoding: .utf8)
            return EpubValidationResult(status: .skipped, reportURL: reportURL, reportText: report)
        }

        let result = try await runner.run(executableURL: epubCheckURL, arguments: [epubURL.path])
        let validationStatus = Self.validationStatus(exitCode: result.exitCode, output: result.output)
        let report = Self.report(
            title: "EPUBCheck \(validationStatus.displayName)",
            body: result.output.isEmpty ? "EPUBCheck completed without output." : result.output,
            conversionLog: conversionLog,
            postProcessReport: postProcessReport
        )
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
        return EpubValidationResult(status: validationStatus, reportURL: reportURL, reportText: report)
    }

    public static func validationStatus(exitCode: Int32, output: String) -> EpubValidationStatus {
        guard exitCode == 0 else { return .failed }
        let lowercasedOutput = output.lowercased()
        if lowercasedOutput.contains("no errors or warnings detected") ||
            lowercasedOutput.contains("0 errors / 0 warnings") {
            return .passed
        }
        if lowercasedOutput.contains("warning") || lowercasedOutput.contains("warn") {
            return .warnings
        }
        return .passed
    }

    private static func report(
        title: String,
        body: String,
        conversionLog: String,
        postProcessReport: String
    ) -> String {
        """
        \(title)

        Validation
        ----------
        \(body)

        \(postProcessReport.isEmpty ? "Comic EPUB post-processing\n--------------------------\nNo post-processing report." : postProcessReport)

        Calibre conversion log
        ----------------------
        \(conversionLog.isEmpty ? "No Calibre log output." : conversionLog)
        """
    }
}

private extension EpubValidationStatus {
    var displayName: String {
        switch self {
        case .passed: "passed"
        case .warnings: "completed with warnings"
        case .failed: "failed"
        case .skipped: "skipped"
        }
    }
}
