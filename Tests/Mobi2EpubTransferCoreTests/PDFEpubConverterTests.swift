import AppKit
import Foundation
import PDFKit
import Testing
@testable import Mobi2EpubTransferCore

struct PDFEpubConverterTests {
    @Test
    func convertsPDFDirectlyWithoutCalibreAndReportsPageProgress() async throws {
        let directory = try TemporaryDirectory()
        let inputURL = directory.url.appendingPathComponent("Illustrated Book.pdf")
        let outputURL = directory.url.appendingPathComponent("Illustrated Book.epub")
        let pageCount = ProcessInfo.processInfo.environment["MOBIVERSE_PDF_BENCHMARK_PAGES"]
            .flatMap(Int.init) ?? 3
        try createPDF(pageCount: pageCount, at: inputURL)
        let progressRecorder = ProgressRecorder()

        let result = try await ConverterService(ebookConvertURL: nil).convert(
            inputURL: inputURL,
            outputURL: outputURL
        ) { update in
            progressRecorder.append(update)
        }

        #expect(result.strategy == .nativePDFFixedLayout)
        #expect(result.postProcessReport?.contains("Image pages: \(pageCount)") == true)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        #expect(progressRecorder.values.last?.completedUnitCount == pageCount)
        #expect(progressRecorder.values.last?.fraction == 1)

        let extractionDirectory = directory.url.appendingPathComponent("preview", isDirectory: true)
        let preview = try await EpubPreviewParser().parse(
            epubURL: outputURL,
            extractionDirectory: extractionDirectory
        )
        if case .imagePages(let pages) = preview.mode {
            #expect(pages.count == pageCount)
            #expect(pages.allSatisfy { $0.width > 0 && $0.height > 0 })
            let firstImageData = try Data(contentsOf: pages[0].imageURL)
            let firstImage = NSBitmapImageRep(data: firstImageData)
            #expect(max(firstImage?.pixelsWide ?? 0, firstImage?.pixelsHigh ?? 0) == 2200)
        } else {
            Issue.record("Expected fixed-layout image page preview")
        }
    }

    private func createPDF(pageCount: Int, at url: URL) throws {
        let document = PDFDocument()
        for index in 0..<pageCount {
            let image = testPageImage(index: index)
            guard let page = PDFPage(image: image) else {
                throw PDFTestError.couldNotCreatePage
            }
            document.insert(page, at: index)
        }
        guard document.write(to: url) else {
            throw PDFTestError.couldNotWriteDocument
        }
    }

    private func testPageImage(index: Int) -> NSImage {
        let width = 600
        let height = 900
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let context = NSGraphicsContext(bitmapImageRep: representation)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSColor(calibratedRed: 0.1, green: 0.16, blue: 0.2, alpha: 1).setFill()
        NSRect(x: 70, y: 100 + index * 20, width: 460, height: 250).fill()
        NSColor(calibratedRed: 0.72, green: 0.28, blue: 0.16, alpha: 1).setFill()
        NSRect(x: 70, y: 390, width: 460, height: 90).fill()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(representation)
        return image
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ConversionProgressUpdate] = []

    var values: [ConversionProgressUpdate] {
        lock.withLock { storage }
    }

    func append(_ update: ConversionProgressUpdate) {
        lock.withLock {
            storage.append(update)
        }
    }
}

private enum PDFTestError: Error {
    case couldNotCreatePage
    case couldNotWriteDocument
}
