import Foundation

public struct PreviewReadingPosition: Codable, Equatable, Sendable {
    public let sectionIndex: Int
    public let pageIndex: Int

    public init(sectionIndex: Int, pageIndex: Int) {
        self.sectionIndex = max(0, sectionIndex)
        self.pageIndex = max(0, pageIndex)
    }
}

public enum LegacyReadingPositionInterpretation: Sendable {
    case page
    case section
}

public struct PreviewReadingPositionStore: Sendable {
    public let storageURL: URL

    public init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
    }

    public func pageIndex(for epubURL: URL) -> Int? {
        position(for: epubURL, legacyInterpretation: .page)?.pageIndex
    }

    public func save(pageIndex: Int, for epubURL: URL) {
        save(
            position: PreviewReadingPosition(sectionIndex: 0, pageIndex: pageIndex),
            for: epubURL
        )
    }

    public func position(
        for epubURL: URL,
        legacyInterpretation: LegacyReadingPositionInterpretation
    ) -> PreviewReadingPosition? {
        guard let stored = loadPositions()[key(for: epubURL)] else { return nil }
        if let sectionIndex = stored.sectionIndex, let pageIndex = stored.pageIndex {
            return PreviewReadingPosition(sectionIndex: sectionIndex, pageIndex: pageIndex)
        }
        guard let legacyIndex = stored.legacyIndex else { return nil }
        switch legacyInterpretation {
        case .page:
            return PreviewReadingPosition(sectionIndex: 0, pageIndex: legacyIndex)
        case .section:
            return PreviewReadingPosition(sectionIndex: legacyIndex, pageIndex: 0)
        }
    }

    public func save(position: PreviewReadingPosition, for epubURL: URL) {
        var positions = loadPositions()
        positions[key(for: epubURL)] = StoredReadingPosition(
            sectionIndex: position.sectionIndex,
            pageIndex: position.pageIndex,
            legacyIndex: nil
        )

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

    private func loadPositions() -> [String: StoredReadingPosition] {
        guard let data = try? Data(contentsOf: storageURL) else { return [:] }
        if let positions = try? JSONDecoder().decode([String: StoredReadingPosition].self, from: data) {
            return positions
        }
        if let legacyPositions = try? JSONDecoder().decode([String: Int].self, from: data) {
            return legacyPositions.mapValues {
                StoredReadingPosition(sectionIndex: nil, pageIndex: nil, legacyIndex: max(0, $0))
            }
        }
        return [:]
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

private struct StoredReadingPosition: Codable {
    let sectionIndex: Int?
    let pageIndex: Int?
    let legacyIndex: Int?
}
