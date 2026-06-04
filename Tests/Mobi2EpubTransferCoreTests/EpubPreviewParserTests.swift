import Foundation
import Testing
@testable import Mobi2EpubTransferCore

struct EpubPreviewParserTests {
    @Test
    func parsesImagePageEPUBAsComicPreview() async throws {
        let directory = try TemporaryDirectory()
        let bookDirectory = directory.url.appendingPathComponent("comic")
        try createMinimalEPUBDirectory(at: bookDirectory, imagePageCount: 3)
        let epubURL = try await zipEPUBDirectory(bookDirectory, outputURL: directory.url.appendingPathComponent("comic.epub"))
        let extractionDirectory = directory.url.appendingPathComponent("preview")

        let book = try await EpubPreviewParser().parse(epubURL: epubURL, extractionDirectory: extractionDirectory)

        #expect(book.title == "Preview Comic")
        #expect(book.readingDirection == .rightToLeft)
        if case .imagePages(let pages) = book.mode {
            #expect(pages.count == 3)
            #expect(pages.first?.imageURL.lastPathComponent == "page-00001.jpg")
        } else {
            Issue.record("Expected image page preview")
        }
    }

    @Test
    func parsesTextEPUBAsWebPreview() async throws {
        let directory = try TemporaryDirectory()
        let bookDirectory = directory.url.appendingPathComponent("text-book")
        try createMinimalEPUBDirectory(at: bookDirectory, imagePageCount: 0)
        let epubURL = try await zipEPUBDirectory(bookDirectory, outputURL: directory.url.appendingPathComponent("text.epub"))
        let extractionDirectory = directory.url.appendingPathComponent("preview")

        let book = try await EpubPreviewParser().parse(epubURL: epubURL, extractionDirectory: extractionDirectory)

        if case .web(let startURL) = book.mode {
            #expect(startURL.lastPathComponent == "chapter.xhtml")
        } else {
            Issue.record("Expected WebView preview")
        }
    }

    private func createMinimalEPUBDirectory(at directory: URL, imagePageCount: Int) throws {
        let metaInfURL = directory.appendingPathComponent("META-INF", isDirectory: true)
        let oebpsURL = directory.appendingPathComponent("OEBPS", isDirectory: true)
        let pagesURL = oebpsURL.appendingPathComponent("pages", isDirectory: true)
        let imagesURL = oebpsURL.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: metaInfURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pagesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)

        try "application/epub+zip".write(to: directory.appendingPathComponent("mimetype"), atomically: true, encoding: .utf8)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """.write(to: metaInfURL.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)

        if imagePageCount > 0 {
            try writeComicPages(count: imagePageCount, pagesURL: pagesURL, imagesURL: imagesURL)
            try comicOPF(pageCount: imagePageCount).write(
                to: oebpsURL.appendingPathComponent("content.opf"),
                atomically: true,
                encoding: .utf8
            )
        } else {
            try """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml">
              <body><p>Hello EPUB</p></body>
            </html>
            """.write(to: pagesURL.appendingPathComponent("chapter.xhtml"), atomically: true, encoding: .utf8)
            try textOPF.write(to: oebpsURL.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)
        }
    }

    private func writeComicPages(count: Int, pagesURL: URL, imagesURL: URL) throws {
        for pageNumber in 1...count {
            let id = String(format: "page-%05d", pageNumber)
            try """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml">
              <body><svg xmlns="http://www.w3.org/2000/svg"><image href="../images/\(id).jpg"/></svg></body>
            </html>
            """.write(to: pagesURL.appendingPathComponent("\(id).xhtml"), atomically: true, encoding: .utf8)
            FileManager.default.createFile(
                atPath: imagesURL.appendingPathComponent("\(id).jpg").path,
                contents: Data([0xFF, 0xD8, 0xFF, 0xD9])
            )
        }
    }

    private func comicOPF(pageCount: Int) -> String {
        let pageItems = (1...pageCount).map { pageNumber in
            let id = String(format: "page-%05d", pageNumber)
            return #"    <item id="\#(id)" href="pages/\#(id).xhtml" media-type="application/xhtml+xml" properties="svg"/>"#
        }.joined(separator: "\n")
        let imageItems = (1...pageCount).map { pageNumber in
            let id = String(format: "page-%05d", pageNumber)
            return #"    <item id="\#(id)-image" href="images/\#(id).jpg" media-type="image/jpeg"/>"#
        }.joined(separator: "\n")
        let spineItems = (1...pageCount).map { pageNumber in
            let id = String(format: "page-%05d", pageNumber)
            return #"    <itemref idref="\#(id)"/>"#
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Preview Comic</dc:title>
          </metadata>
          <manifest>
        \(pageItems)
        \(imageItems)
          </manifest>
          <spine page-progression-direction="rtl">
        \(spineItems)
          </spine>
        </package>
        """
    }

    private var textOPF: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Preview Text</dc:title>
          </metadata>
          <manifest>
            <item id="chapter" href="pages/chapter.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="chapter"/>
          </spine>
        </package>
        """
    }

    private func zipEPUBDirectory(_ directory: URL, outputURL: URL) async throws -> URL {
        let result = try await ProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-X", "-q", "-r", outputURL.path, "."],
            currentDirectoryURL: directory
        )
        #expect(result.exitCode == 0)
        return outputURL
    }
}
