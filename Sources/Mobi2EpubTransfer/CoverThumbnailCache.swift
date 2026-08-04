import AppKit
import Foundation
import Mobi2EpubTransferCore

struct CoverThumbnailCache {
    private let cacheDirectory: URL
    private let fileManager: FileManager
    private let thumbnailSize = NSSize(width: 220, height: 320)
    private let showcaseSize = NSSize(width: 880, height: 1280)

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
        guard let cacheURL = cacheURL(for: task, rendition: .thumbnail) else { return nil }
        return NSImage(contentsOf: cacheURL)
    }

    func showcaseImage(for task: ConversionTask) -> NSImage? {
        guard let cacheURL = cacheURL(for: task, rendition: .showcase) else { return nil }
        return NSImage(contentsOf: cacheURL)
    }

    func save(_ image: NSImage, for task: ConversionTask) {
        save(image, for: task, rendition: .thumbnail)
    }

    func saveShowcase(_ image: NSImage, for task: ConversionTask) {
        save(image, for: task, rendition: .showcase)
    }

    private func save(_ image: NSImage, for task: ConversionTask, rendition: Rendition) {
        guard let cacheURL = cacheURL(for: task, rendition: rendition) else { return }
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let thumbnail = thumbnailImage(from: image, targetSize: rendition.targetSize(in: self))
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

    private func cacheURL(for task: ConversionTask, rendition: Rendition) -> URL? {
        guard let outputURL = task.outputURL else { return nil }
        guard let attributes = try? fileManager.attributesOfItem(atPath: outputURL.path) else { return nil }

        let modificationMilliseconds: Int
        if let modificationDate = attributes[.modificationDate] as? Date {
            modificationMilliseconds = Int(modificationDate.timeIntervalSince1970 * 1000)
        } else {
            modificationMilliseconds = 0
        }

        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let suffix = rendition == .showcase ? "-showcase" : ""
        let fileName = "\(task.id.uuidString)-\(modificationMilliseconds)-\(fileSize)\(suffix).png"
        return cacheDirectory.appendingPathComponent(fileName)
    }

    private func thumbnailImage(from image: NSImage, targetSize: NSSize) -> NSImage {
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        defer { thumbnail.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: targetSize).fill()
        NSGraphicsContext.current?.imageInterpolation = .high

        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return image
        }

        let targetAspectRatio = targetSize.width / targetSize.height
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
            in: NSRect(origin: .zero, size: targetSize),
            from: sourceRect,
            operation: .copy,
            fraction: 1
        )
        return thumbnail
    }

    private enum Rendition {
        case thumbnail
        case showcase

        func targetSize(in cache: CoverThumbnailCache) -> NSSize {
            switch self {
            case .thumbnail: cache.thumbnailSize
            case .showcase: cache.showcaseSize
            }
        }
    }
}
