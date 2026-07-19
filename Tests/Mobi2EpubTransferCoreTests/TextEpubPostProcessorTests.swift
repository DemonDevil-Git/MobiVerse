import Foundation
import Testing
@testable import Mobi2EpubTransferCore

struct TextEpubPostProcessorTests {
    @Test
    func preservesRubyAndRepairsInvalidStructure() async throws {
        let directory = try TemporaryDirectory()
        let source = directory.url.appendingPathComponent("book")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("text"), withIntermediateDirectories: true)
        try "application/epub+zip".write(to: source.appendingPathComponent("mimetype"), atomically: true, encoding: .utf8)
        try """
        <?xml version="1.0"?>
        <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
          <rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """.write(to: source.appendingPathComponent("META-INF/container.xml"), atomically: true, encoding: .utf8)
        try """
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata/><manifest>
        <item id="chapter" href="text/chapter.xhtml" media-type="application/xhtml+xml"/>
        <item id="css" href="page_styles.css" media-type="text/css"/>
        </manifest><spine><itemref idref="chapter"/></spine></package>
        """.write(to: source.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)
        try """
        <html xmlns="http://www.w3.org/1999/xhtml"><head><link rel="stylesheet" href="../page_styles.css"/></head>
        <body id="0:chapter"><p><ruby>日本<rt>にほん</rt></ruby></p><a href="#0:chapter">Back</a></body></html>
        """.write(to: source.appendingPathComponent("text/chapter.xhtml"), atomically: true, encoding: .utf8)
        try "@font-face { font-family: test; src: url(styles/MISSING); }\nbody { margin: 1em; }"
            .write(to: source.appendingPathComponent("page_styles.css"), atomically: true, encoding: .utf8)
        try """
        <ncx><navMap>
        <navPoint playOrder="0"><content src="text/chapter.xhtml"/></navPoint>
        <navPoint playOrder="1"><content src="text/chapter.xhtml"/></navPoint>
        </navMap></ncx>
        """.write(to: source.appendingPathComponent("toc.ncx"), atomically: true, encoding: .utf8)

        let epub = directory.url.appendingPathComponent("book.epub")
        let zipped = try await ProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-Xqr", epub.path, "."],
            currentDirectoryURL: source
        )
        #expect(zipped.exitCode == 0)

        let result = try await TextEpubPostProcessor().process(epubURL: epub)
        let chapter = try await unzip(epub, "text/chapter.xhtml")
        let css = try await unzip(epub, "page_styles.css")
        let ncx = try await unzip(epub, "toc.ncx")

        #expect(result.repairedIdentifierCount == 1)
        #expect(result.removedBrokenResourceCount == 1)
        #expect(result.reorderedNavigationCount == 2)
        #expect(chapter.contains("<ruby>日本<rt>にほん</rt></ruby>"))
        #expect(chapter.contains(#"id="mv-0-chapter""#))
        #expect(chapter.contains(##"href="#mv-0-chapter""##))
        #expect(!css.contains("MISSING"))
        #expect(css.contains("body { margin: 1em; }"))
        #expect(ncx.contains(#"playOrder="1""#))
        #expect(ncx.contains(#"playOrder="2""#))
    }

    private func unzip(_ epub: URL, _ path: String) async throws -> String {
        let result = try await ProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-p", epub.path, path]
        )
        #expect(result.exitCode == 0)
        return result.output
    }
}
