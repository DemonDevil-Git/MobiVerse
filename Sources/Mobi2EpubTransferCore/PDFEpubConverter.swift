import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct PDFEpubConverter {
    private static let maximumImageLongEdge = 2200
    private static let jpegQuality = 0.86

    private let runner: any ProcessRunning
    private let fileManager: FileManager

    init(runner: any ProcessRunning, fileManager: FileManager = .default) {
        self.runner = runner
        self.fileManager = fileManager
    }

    func convert(
        inputURL: URL,
        outputURL: URL,
        readingDirection: EpubReadingDirection,
        progressHandler: ConversionProgressHandler?
    ) async throws -> ConversionRunResult {
        let workingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MobiVersePDFConversion", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let imagesDirectory = workingDirectory.appendingPathComponent("images", isDirectory: true)
        try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: workingDirectory)
        }

        let renderResult: PDFRenderResult
        do {
            renderResult = try await renderPages(
                inputURL: inputURL,
                imagesDirectory: imagesDirectory,
                progressHandler: progressHandler
            )
        } catch let error as ConversionServiceError {
            throw error
        } catch {
            throw ConversionServiceError(
                kind: .inputUnreadable,
                message: "The PDF could not be rendered or appears to be damaged.",
                log: error.localizedDescription
            )
        }

        progressHandler?(
            ConversionProgressUpdate(
                fraction: 0.92,
                message: "Packaging \(renderResult.pageCount) pages into EPUB",
                completedUnitCount: renderResult.pageCount,
                totalUnitCount: renderResult.pageCount
            )
        )

        let postProcessResult = try await ComicEpubPostProcessor(runner: runner).buildFixedLayoutEPUB(
            title: renderResult.title,
            imageFiles: renderResult.imageURLs,
            outputURL: outputURL,
            readingDirection: readingDirection
        )

        progressHandler?(
            ConversionProgressUpdate(
                fraction: 1,
                message: "PDF conversion complete",
                completedUnitCount: renderResult.pageCount,
                totalUnitCount: renderResult.pageCount
            )
        )

        let log = """
        Native PDF conversion
        ---------------------
        Renderer: PDFKit
        Pages: \(renderResult.pageCount)
        Maximum image edge: \(Self.maximumImageLongEdge) px
        JPEG quality: \(Self.jpegQuality)
        Calibre PDF reflow: skipped
        """

        return ConversionRunResult(
            outputURL: outputURL,
            log: log,
            strategy: .nativePDFFixedLayout,
            postProcessReport: postProcessResult.reportText
        )
    }

    private func renderPages(
        inputURL: URL,
        imagesDirectory: URL,
        progressHandler: ConversionProgressHandler?
    ) async throws -> PDFRenderResult {
        try await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(url: inputURL), document.pageCount > 0 else {
                throw ConversionServiceError(
                    kind: .inputUnreadable,
                    message: "The PDF could not be opened or contains no pages."
                )
            }
            guard !document.isLocked else {
                throw ConversionServiceError(
                    kind: .drmProtected,
                    message: "This PDF is password protected. MobiVerse does not remove protection."
                )
            }

            let title = inputURL.deletingPathExtension().lastPathComponent
            let pageCount = document.pageCount
            var imageURLs: [URL] = []
            imageURLs.reserveCapacity(pageCount)

            for pageIndex in 0..<pageCount {
                guard let page = document.page(at: pageIndex) else {
                    throw ConversionServiceError(
                        kind: .inputUnreadable,
                        message: "PDF page \(pageIndex + 1) could not be read."
                    )
                }

                let imageURL = imagesDirectory
                    .appendingPathComponent(String(format: "page-%05d.jpg", pageIndex + 1))
                try autoreleasepool {
                    let pageBounds = page.bounds(for: .cropBox)
                    let targetSize = Self.renderSize(for: pageBounds.size)
                    let thumbnail = page.thumbnail(of: targetSize, for: .cropBox)
                    guard let image = Self.cgImage(from: thumbnail) else {
                        throw ConversionServiceError(
                            kind: .conversionFailed,
                            message: "PDF page \(pageIndex + 1) could not be rendered."
                        )
                    }
                    try Self.writeJPEG(image, to: imageURL)
                }
                imageURLs.append(imageURL)

                let completed = pageIndex + 1
                progressHandler?(
                    ConversionProgressUpdate(
                        fraction: 0.04 + (Double(completed) / Double(pageCount)) * 0.84,
                        message: "Rendering PDF page \(completed) of \(pageCount)",
                        completedUnitCount: completed,
                        totalUnitCount: pageCount
                    )
                )
            }

            return PDFRenderResult(title: title, pageCount: pageCount, imageURLs: imageURLs)
        }.value
    }

    private static func renderSize(for pageSize: CGSize) -> CGSize {
        let width = max(1, pageSize.width)
        let height = max(1, pageSize.height)
        let scale = Double(maximumImageLongEdge) / max(width, height)
        return CGSize(
            width: max(1, (width * scale).rounded()),
            height: max(1, (height * scale).rounded())
        )
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ConversionServiceError(
                kind: .outputPermissionDenied,
                message: "The rendered PDF page could not be written."
            )
        }

        let options = [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionServiceError(
                kind: .outputPermissionDenied,
                message: "The rendered PDF page could not be saved."
            )
        }
    }
}

private struct PDFRenderResult: Sendable {
    let title: String
    let pageCount: Int
    let imageURLs: [URL]
}
