import Foundation

public struct ProcessRunResult: Equatable, Sendable {
    public let exitCode: Int32
    public let output: String

    public init(exitCode: Int32, output: String) {
        self.exitCode = exitCode
        self.output = output
    }
}

public protocol ProcessRunning: Sendable {
    func run(executableURL: URL, arguments: [String]) async throws -> ProcessRunResult
    func run(executableURL: URL, arguments: [String], currentDirectoryURL: URL?) async throws -> ProcessRunResult
}

public struct ProcessRunner: ProcessRunning {
    public init() {}

    public func run(executableURL: URL, arguments: [String]) async throws -> ProcessRunResult {
        try await run(executableURL: executableURL, arguments: arguments, currentDirectoryURL: nil)
    }

    public func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?
    ) async throws -> ProcessRunResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            let finalOutput = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            return ProcessRunResult(
                exitCode: process.terminationStatus,
                output: String(data: finalOutput, encoding: .utf8) ?? ""
            )
        }.value
    }
}
