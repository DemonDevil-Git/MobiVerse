import Foundation

public struct PreviewReadingPositionStore: Sendable {
    public let storageURL: URL

    public init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
    }

    public func pageIndex(for epubURL: URL) -> Int? {
        loadPositions()[key(for: epubURL)].map { max(0, $0) }
    }

    public func save(pageIndex: Int, for epubURL: URL) {
        var positions = loadPositions()
        positions[key(for: epubURL)] = max(0, pageIndex)

        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(positions)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            // A preview must remain usable even when reading position cannot be persisted.
        }
    }

    private func loadPositions() -> [String: Int] {
        guard
            let data = try? Data(contentsOf: storageURL),
            let positions = try? JSONDecoder().decode([String: Int].self, from: data)
        else {
            return [:]
        }
        return positions
    }

    private func key(for epubURL: URL) -> String {
        epubURL.standardizedFileURL.path
    }

    private static func defaultStorageURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("MobiVerse", isDirectory: true)
            .appendingPathComponent("preview-reading-positions.json")
    }
}
