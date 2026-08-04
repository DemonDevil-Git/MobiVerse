import Foundation
import Mobi2EpubTransferCore

struct BookMetadataCache {
    private let cacheDirectory: URL
    private let fileManager: FileManager

    init(cacheDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.cacheDirectory = baseURL
                .appendingPathComponent("MobiVerse", isDirectory: true)
                .appendingPathComponent("Metadata", isDirectory: true)
        }
    }

    func metadata(for task: ConversionTask) -> EpubBookMetadata? {
        guard let url = cacheURL(for: task), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(EpubBookMetadata.self, from: data)
    }

    func save(_ metadata: EpubBookMetadata, for task: ConversionTask) {
        guard let url = cacheURL(for: task) else { return }
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    func removeMetadata(for task: ConversionTask) {
        guard fileManager.fileExists(atPath: cacheDirectory.path) else { return }
        let prefix = "\(task.id.uuidString)-"
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? fileManager.removeItem(at: file)
        }
    }

    private func cacheURL(for task: ConversionTask) -> URL? {
        guard let outputURL = task.outputURL else { return nil }
        guard let attributes = try? fileManager.attributesOfItem(atPath: outputURL.path) else { return nil }
        let modified = (attributes[.modificationDate] as? Date).map { Int($0.timeIntervalSince1970 * 1000) } ?? 0
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return cacheDirectory.appendingPathComponent("\(task.id.uuidString)-\(modified)-\(size).json")
    }
}
