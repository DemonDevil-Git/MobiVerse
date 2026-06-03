import Foundation

public struct ConversionHistoryStore: Sendable {
    public let historyURL: URL

    public init(historyURL: URL? = nil) {
        self.historyURL = historyURL ?? Self.defaultHistoryURL()
    }

    public func load() -> [ConversionTask] {
        guard FileManager.default.fileExists(atPath: historyURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: historyURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let tasks = try decoder.decode([ConversionTask].self, from: data)
            return tasks.map(Self.normalizedForRestore)
        } catch {
            return []
        }
    }

    public func save(_ tasks: [ConversionTask]) {
        do {
            let directoryURL = historyURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(tasks)
            try data.write(to: historyURL, options: [.atomic])
        } catch {
            // History is helpful, but conversion should not fail because persistence failed.
        }
    }

    private static func defaultHistoryURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("MobiVerse", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    private static func normalizedForRestore(_ task: ConversionTask) -> ConversionTask {
        var restored = task

        switch restored.status {
        case .checkingTools, .converting, .validating:
            restored.status = .failed
            restored.progress = 1
            restored.statusMessage = "Interrupted before completion"
            if restored.completedAt == nil {
                restored.completedAt = Date()
            }
        case .queued:
            restored.progress = 0
            restored.statusMessage = "Waiting"
        case .succeeded, .succeededWithWarnings, .failed:
            break
        }

        return restored
    }
}
