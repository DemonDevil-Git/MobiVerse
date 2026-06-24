import AppKit
import Foundation
import Mobi2EpubTransferCore

struct CoverThumbnailCache {
    private let cacheDirectory: URL
    private let fileManager: FileManager
    private let thumbnailSize = NSSize(width: 220, height: 320)

    init(cacheDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.cacheDirectory = baseURL
                .appendingPathComponent("MobiVerse", isDirectory: true)
                .appendingPathComponent("Covers", isDirectory: true)
        }
    }

    func image(for task: ConversionTask) -> NSImage? {
        guard let cacheURL = cacheURL(for: task) else { return nil }
        return NSImage(contentsOf: cacheURL)
    }

    func save(_ image: NSImage, for task: ConversionTask) {
        guard let cacheURL = cacheURL(for: task) else { return }
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let thumbnail = thumbnailImage(from: image)
            guard
                let tiffData = thumbnail.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiffData),
                let pngData = bitmap.representation(using: .png, properties: [:])
            else {
                return
            }
            try pngData.write(to: cacheURL, options: [.atomic])
        } catch {
            return
        }
    }

    func removeImage(for task: ConversionTask) {
        guard fileManager.fileExists(atPath: cacheDirectory.path) else { return }
        let prefix = "\(task.id.uuidString)-"
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? fileManager.removeItem(at: file)
        }
    }

    private func cacheURL(for task: ConversionTask) -> URL? {
        guard let outputURL = task.outputURL else { return nil }
        guard let attributes = try? fileManager.attributesOfItem(atPath: outputURL.path) else { return nil }

        let modificationMilliseconds: Int
        if let modificationDate = attributes[.modificationDate] as? Date {
            modificationMilliseconds = Int(modificationDate.timeIntervalSince1970 * 1000)
        } else {
            modificationMilliseconds = 0
        }

        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let fileName = "\(task.id.uuidString)-\(modificationMilliseconds)-\(fileSize).png"
        return cacheDirectory.appendingPathComponent(fileName)
    }

    private func thumbnailImage(from image: NSImage) -> NSImage {
        let thumbnail = NSImage(size: thumbnailSize)
        thumbnail.lockFocus()
        defer { thumbnail.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: thumbnailSize).fill()
        NSGraphicsContext.current?.imageInterpolation = .high

        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return image
        }

        let targetAspectRatio = thumbnailSize.width / thumbnailSize.height
        let sourceAspectRatio = sourceSize.width / sourceSize.height
        let sourceRect: NSRect

        if sourceAspectRatio > targetAspectRatio {
            let croppedWidth = sourceSize.height * targetAspectRatio
            sourceRect = NSRect(
                x: (sourceSize.width - croppedWidth) / 2,
                y: 0,
                width: croppedWidth,
                height: sourceSize.height
            )
        } else {
            let croppedHeight = sourceSize.width / targetAspectRatio
            sourceRect = NSRect(
                x: 0,
                y: (sourceSize.height - croppedHeight) / 2,
                width: sourceSize.width,
                height: croppedHeight
            )
        }

        image.draw(
            in: NSRect(origin: .zero, size: thumbnailSize),
            from: sourceRect,
            operation: .copy,
            fraction: 1
        )
        return thumbnail
    }
}

