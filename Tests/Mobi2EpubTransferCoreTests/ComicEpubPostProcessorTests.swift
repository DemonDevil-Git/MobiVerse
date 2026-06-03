import Foundation
import Testing
@testable import Mobi2EpubTransferCore

struct ComicEpubPostProcessorTests {
    @Test
    func postProcessorRewritesComicLayoutMetadataAndTOC() async throws {
        let directory = try TemporaryDirectory()
        let sourceDirectory = directory.url.appendingPathComponent("book")
        try FileManager.default.createDirectory(
            at: sourceDirectory.appendingPathComponent("text"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: sourceDirectory.appendingPathComponent("images"),
            withIntermediateDirectories: true
        )

        try """
        body.calibre { margin: 0 5pt; }
        .calibre2 { width: 1072px; height: 1448px; }
        """.write(to: sourceDirectory.appendingPathComponent("stylesheet.css"), atomically: true, encoding: .utf8)
        try "@page { margin-top: 5pt; }".write(
            to: sourceDirectory.appendingPathComponent("page_styles.css"),
            atomically: true,
            encoding: .utf8
        )
        try opf.write(to: sourceDirectory.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)
        try ncx.write(to: sourceDirectory.appendingPathComponent("toc.ncx"), atomically: true, encoding: .utf8)

        for index in 0..<30 {
            let number = String(format: "%04d", index)
            try "<html><body><img src=\"../images/\(number).jpeg\"/></body></html>".write(
                to: sourceDirectory.appendingPathComponent("text/part\(number).html"),
                atomically: true,
                encoding: .utf8
            )
            FileManager.default.createFile(
                atPath: sourceDirectory.appendingPathComponent("images/\(number).jpeg").path,
                contents: Data([0xFF, 0xD8, 0xFF, 0xD9])
            )
        }

        let epubURL = directory.url.appendingPathComponent("comic.epub")
        let zipRunner = ProcessRunner()
        let zipResult = try await zipRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-X", "-q", "-r", epubURL.path, "."],
            currentDirectoryURL: sourceDirectory
        )
        #expect(zipResult.exitCode == 0)

        let result = try await ComicEpubPostProcessor().process(epubURL: epubURL)

        #expect(result.pageCount == 30)
        #expect(result.imageCount == 30)
        #expect(result.tocEntryCount == 2)
        #expect(result.appliedRightToLeftMetadata)
        #expect(result.appliedFixedLayoutMetadata)

        let stylesheet = try await unzipContent(epubURL: epubURL, path: "stylesheet.css")
        let updatedOPF = try await unzipContent(epubURL: epubURL, path: "content.opf")
        let updatedNCX = try await unzipContent(epubURL: epubURL, path: "toc.ncx")
        let firstPage = try await unzipContent(epubURL: epubURL, path: "text/part0000.html")

        #expect(stylesheet.contains("overflow: hidden"))
        #expect(!stylesheet.contains("1072px"))
        #expect(updatedOPF.contains("page-progression-direction=\"rtl\""))
        #expect(updatedOPF.contains("vertical-rl"))
        #expect(updatedOPF.contains(#"<meta property="rendition:layout">pre-paginated</meta>"#))
        #expect(updatedOPF.contains(#"<meta name="fixed-layout" content="true"/>"#))
        #expect(updatedNCX.contains("Page 2"))
        #expect(firstPage.contains(#"<meta name="viewport" content="width=1067, height=1600"/>"#))
        #expect(firstPage.contains(#"<style type="text/css">"#))
        #expect(!firstPage.contains("background-image"))
        #expect(firstPage.contains(#"<img class="mobi-verse-image""#))
        #expect(firstPage.contains(#"src="../images/0000.jpeg""#))
        #expect(firstPage.contains(#"width="1067""#))
        #expect(firstPage.contains(#"height="1600""#))
        #expect(firstPage.contains("width: 1067px"))
        #expect(firstPage.contains("height: 1600px"))
        #expect(!firstPage.contains(#"href="../stylesheet.css""#))
        #expect(!firstPage.contains(#"href="../page_styles.css""#))
        #expect(!firstPage.contains("<svg"))
    }

    private var opf: String {
        """
        <?xml version='1.0' encoding='utf-8'?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uuid_id">
          <metadata xmlns:opf="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Comic</dc:title>
            <meta name="primary-writing-mode" content="horizontal-lr"/>
          </metadata>
          <manifest>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
          </manifest>
          <spine toc="ncx">
          </spine>
        </package>
        """
    }

    private var ncx: String {
        """
        <?xml version='1.0' encoding='utf-8'?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <head></head>
          <docTitle><text>Comic</text></docTitle>
          <navMap>
            <navPoint id="start" playOrder="1"><navLabel><text>Start</text></navLabel><content src="titlepage.xhtml"/></navPoint>
          </navMap>
        </ncx>
        """
    }

    private func unzipContent(epubURL: URL, path: String) async throws -> String {
        let result = try await ProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-p", epubURL.path, path]
        )
        #expect(result.exitCode == 0)
        return result.output
    }
}
