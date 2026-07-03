import Foundation
import Testing
@testable import Mobi2EpubTransferCore

struct EpubPreviewParserTests {
    @Test
    func rejectsPathsOutsideEPUBRoot() throws {
        let directory = try TemporaryDirectory()
        let root = directory.url.appendingPathComponent("book", isDirectory: true)
        let pages = root.appendingPathComponent("OEBPS/pages", isDirectory: true)
        try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
        let outside = directory.url.appendingPathComponent("private.xhtml")
        try "secret".write(to: outside, atomically: true, encoding: .utf8)

        #expect(EpubPathSecurity.resolve("../../../private.xhtml", relativeTo: pages, containedIn: root) == nil)
        #expect(EpubPathSecurity.resolve("%2E%2E/%2E%2E/%2E%2E/private.xhtml", relativeTo: pages, containedIn: root) == nil)
        #expect(EpubPathSecurity.resolve(outside.path, relativeTo: pages, containedIn: root) == nil)
        #expect(EpubPathSecurity.resolve("https://example.com/book.xhtml", relativeTo: pages, containedIn: root) == nil)
    }

    @Test
    func acceptsNormalizedPathsInsideEPUBRoot() throws {
        let directory = try TemporaryDirectory()
        let root = directory.url.appendingPathComponent("book", isDirectory: true)
        let pages = root.appendingPathComponent("OEBPS/pages", isDirectory: true)
        let images = root.appendingPathComponent("OEBPS/images", isDirectory: true)
        try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)

        let result = EpubPathSecurity.resolve("../images/cover%20image.jpg#page", relativeTo: pages, containedIn: root)
        #expect(result == images.appendingPathComponent("cover image.jpg"))
    }

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

        if case .web(let spineURLs) = book.mode {
            #expect(spineURLs.map(\.lastPathComponent) == ["chapter.xhtml"])
        } else {
            Issue.record("Expected WebView preview")
        }
    }

    @Test
    func textEPUBIncludesEverySpineDocumentAndIsNotMistakenForComic() async throws {
        let directory = try TemporaryDirectory()
        let bookDirectory = directory.url.appendingPathComponent("illustrated-text-book")
        try createIllustratedTextEPUBDirectory(at: bookDirectory)
        let epubURL = try await zipEPUBDirectory(
            bookDirectory,
            outputURL: directory.url.appendingPathComponent("illustrated-text.epub")
        )

        let book = try await EpubPreviewParser().parse(
            epubURL: epubURL,
            extractionDirectory: directory.url.appendingPathComponent("preview")
        )

        if case .web(let spineURLs) = book.mode {
            #expect(spineURLs.map(\.lastPathComponent) == ["cover.xhtml", "chapter-1.xhtml", "chapter-2.xhtml"])
        } else {
            Issue.record("Expected illustrated text EPUB to use WebView preview")
        }
    }

    @Test
    func extractsCoverImageFromEPUBManifest() async throws {
        let directory = try TemporaryDirectory()
        let bookDirectory = directory.url.appendingPathComponent("cover-book")
        try createMinimalEPUBDirectory(at: bookDirectory, imagePageCount: 0)
        let imagesURL = bookDirectory.appendingPathComponent("OEBPS/images", isDirectory: true)
        FileManager.default.createFile(
            atPath: imagesURL.appendingPathComponent("cover.jpg").path,
            contents: Data([0xFF, 0xD8, 0xFF, 0xD9])
        )
        try coverOPF.write(
            to: bookDirectory.appendingPathComponent("OEBPS/content.opf"),
            atomically: true,
            encoding: .utf8
        )
        let epubURL = try await zipEPUBDirectory(bookDirectory, outputURL: directory.url.appendingPathComponent("cover.epub"))
        let extractionDirectory = directory.url.appendingPathComponent("cover-preview")

        let coverURL = try await EpubCoverImageExtractor().coverImageURL(
            epubURL: epubURL,
            extractionDirectory: extractionDirectory
        )

        #expect(coverURL?.lastPathComponent == "cover.jpg")
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

    private func createIllustratedTextEPUBDirectory(at directory: URL) throws {
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
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """.write(to: metaInfURL.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)

        try """
        <html xmlns="http://www.w3.org/1999/xhtml"><body><img src="../images/cover.jpg"/></body></html>
        """.write(to: pagesURL.appendingPathComponent("cover.xhtml"), atomically: true, encoding: .utf8)
        try """
        <html xmlns="http://www.w3.org/1999/xhtml"><body><h1>Chapter One</h1><img src="../images/figure.jpg"/><p>Body text.</p></body></html>
        """.write(to: pagesURL.appendingPathComponent("chapter-1.xhtml"), atomically: true, encoding: .utf8)
        try """
        <html xmlns="http://www.w3.org/1999/xhtml"><body><h1>Chapter Two</h1><p>More body text.</p></body></html>
        """.write(to: pagesURL.appendingPathComponent("chapter-2.xhtml"), atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: imagesURL.appendingPathComponent("cover.jpg").path, contents: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        FileManager.default.createFile(atPath: imagesURL.appendingPathComponent("figure.jpg").path, contents: Data([0xFF, 0xD8, 0xFF, 0xD9]))

        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Illustrated Text</dc:title></metadata>
          <manifest>
            <item id="cover" href="pages/cover.xhtml" media-type="application/xhtml+xml"/>
            <item id="chapter-1" href="pages/chapter-1.xhtml" media-type="application/xhtml+xml"/>
            <item id="chapter-2" href="pages/chapter-2.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="cover"/><itemref idref="chapter-1"/><itemref idref="chapter-2"/></spine>
        </package>
        """.write(to: oebpsURL.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)
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

    private var coverOPF: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Preview Text</dc:title>
            <meta name="cover" content="cover-image"/>
          </metadata>
          <manifest>
            <item id="chapter" href="pages/chapter.xhtml" media-type="application/xhtml+xml"/>
            <item id="cover-image" href="images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>
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
