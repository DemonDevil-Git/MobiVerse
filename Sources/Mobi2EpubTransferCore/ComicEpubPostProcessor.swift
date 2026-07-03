import Foundation

public struct ComicPostProcessResult: Equatable, Sendable {
    public let pageCount: Int
    public let imageCount: Int
    public let tocEntryCount: Int
    public let removedFixedImageSizing: Bool
    public let appliedRightToLeftMetadata: Bool
    public let appliedFixedLayoutMetadata: Bool

    public var reportText: String {
        """
        Comic EPUB post-processing
        --------------------------
        Image pages: \(pageCount)
        Images: \(imageCount)
        TOC entries: \(tocEntryCount)
        Full-page responsive image CSS: \(removedFixedImageSizing ? "applied" : "not applied")
        Right-to-left manga metadata: \(appliedRightToLeftMetadata ? "applied" : "not applied")
        Fixed-layout comic pages: \(appliedFixedLayoutMetadata ? "applied" : "not applied")
        """
    }
}

private struct OPFRewriteResult: Equatable {
    let appliedRightToLeftMetadata: Bool
    let appliedFixedLayoutMetadata: Bool
}

private struct ImageDimensions: Equatable {
    let width: Int
    let height: Int

    func scaledToFit(maxLongEdge: Int) -> ImageDimensions {
        let longEdge = max(width, height)
        guard longEdge > maxLongEdge else { return self }
        let scale = Double(maxLongEdge) / Double(longEdge)
        return ImageDimensions(
            width: max(1, Int((Double(width) * scale).rounded())),
            height: max(1, Int((Double(height) * scale).rounded()))
        )
    }
}

private struct RebuiltPage: Equatable {
    let id: String
    let htmlFileName: String
    let imageFileName: String
    let imageMediaType: String
    let layoutDimensions: ImageDimensions
}

public struct ComicEpubPostProcessor {
    private static let maximumImageLongEdge = 2200
    private static let maximumLayoutLongEdge = 1600

    private let runner: any ProcessRunning
    private let fileManager: FileManager

    public init(runner: any ProcessRunning = ProcessRunner(), fileManager: FileManager = .default) {
        self.runner = runner
        self.fileManager = fileManager
    }

    public func process(epubURL: URL) async throws -> ComicPostProcessResult {
        let workingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("Mobi2EpubPostProcess")
            .appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: workingDirectory)
        }

        let unzipResult = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-q", epubURL.path, "-d", workingDirectory.path]
        )
        guard unzipResult.exitCode == 0 else {
            throw ComicPostProcessError.unzipFailed(unzipResult.output)
        }

        let imageFiles = try discoveredImageFiles(in: workingDirectory)
        try await normalizeLargeImages(imageFiles)
        let title = title(fromOPFAt: packageDocumentURL(in: workingDirectory))
            ?? epubURL.deletingPathExtension().lastPathComponent

        return try await buildFixedLayoutEPUB(
            title: title,
            imageFiles: imageFiles,
            outputURL: epubURL
        )
    }

    public func buildFixedLayoutEPUB(
        title: String,
        imageFiles: [URL],
        outputURL: URL
    ) async throws -> ComicPostProcessResult {
        let rebuiltDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MobiVerseRebuiltEPUB")
            .appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: rebuiltDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: rebuiltDirectory)
        }

        let pages = try rebuildFixedLayoutEPUB(
            title: title,
            imageFiles: imageFiles,
            outputDirectory: rebuiltDirectory
        )
        let tocEntryCount = tocEntries(for: pages).count

        let replacementURL = outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(outputURL.deletingPathExtension().lastPathComponent)-postprocessed.epub")
        try? fileManager.removeItem(at: replacementURL)

        let mimetypeZipResult = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-X", "-q", "-0", replacementURL.path, "mimetype"],
            currentDirectoryURL: rebuiltDirectory
        )
        guard mimetypeZipResult.exitCode == 0 else {
            throw ComicPostProcessError.zipFailed(mimetypeZipResult.output)
        }

        let zipResult = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-X", "-q", "-0", "-r", replacementURL.path, "META-INF", "OEBPS"],
            currentDirectoryURL: rebuiltDirectory
        )
        guard zipResult.exitCode == 0 else {
            throw ComicPostProcessError.zipFailed(zipResult.output)
        }
        if fileManager.fileExists(atPath: outputURL.path) {
            _ = try fileManager.replaceItemAt(outputURL, withItemAt: replacementURL)
        } else {
            try fileManager.moveItem(at: replacementURL, to: outputURL)
        }

        return ComicPostProcessResult(
            pageCount: pages.count,
            imageCount: imageFiles.count,
            tocEntryCount: tocEntryCount,
            removedFixedImageSizing: true,
            appliedRightToLeftMetadata: true,
            appliedFixedLayoutMetadata: !pages.isEmpty
        )
    }

    private func writeAppleBooksDisplayOptions(in directory: URL) throws {
        let metaInfURL = directory.appendingPathComponent("META-INF", isDirectory: true)
        try fileManager.createDirectory(at: metaInfURL, withIntermediateDirectories: true)
        let displayOptions = """
        <?xml version="1.0" encoding="UTF-8"?>
        <display_options>
          <platform name="*">
            <option name="fixed-layout">true</option>
            <option name="open-to-spread">false</option>
            <option name="specified-fonts">false</option>
          </platform>
        </display_options>
        """
        try displayOptions.write(
            to: metaInfURL.appendingPathComponent("com.apple.ibooks.display-options.xml"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func rebuildFixedLayoutEPUB(
        title: String,
        imageFiles: [URL],
        outputDirectory: URL
    ) throws -> [RebuiltPage] {
        let metaInfURL = outputDirectory.appendingPathComponent("META-INF", isDirectory: true)
        let oebpsURL = outputDirectory.appendingPathComponent("OEBPS", isDirectory: true)
        let pagesURL = oebpsURL.appendingPathComponent("pages", isDirectory: true)
        let imagesURL = oebpsURL.appendingPathComponent("images", isDirectory: true)
        try fileManager.createDirectory(at: metaInfURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: pagesURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true)

        try "application/epub+zip".write(
            to: outputDirectory.appendingPathComponent("mimetype"),
            atomically: true,
            encoding: .utf8
        )
        try writeContainerXML(in: metaInfURL)
        try writeAppleBooksDisplayOptions(in: outputDirectory)

        let pages = try imageFiles.enumerated().map { index, sourceImageURL in
            try rebuildPage(
                index: index,
                sourceImageURL: sourceImageURL,
                pagesDirectory: pagesURL,
                imagesDirectory: imagesURL
            )
        }

        try writeNavigation(title: title, pages: pages, in: oebpsURL)
        try writeContentOPF(title: title, pages: pages, in: oebpsURL)
        return pages
    }

    private func writeContainerXML(in metaInfURL: URL) throws {
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        try container.write(
            to: metaInfURL.appendingPathComponent("container.xml"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func rebuildPage(
        index: Int,
        sourceImageURL: URL,
        pagesDirectory: URL,
        imagesDirectory: URL
    ) throws -> RebuiltPage {
        let id = String(format: "page-%05d", index + 1)
        let imageFileName = "\(id).\(normalizedImageExtension(for: sourceImageURL))"
        let htmlFileName = "\(id).xhtml"
        let copiedImageURL = imagesDirectory.appendingPathComponent(imageFileName)
        try fileManager.copyItem(at: sourceImageURL, to: copiedImageURL)

        let dimensions = imageDimensions(at: copiedImageURL) ?? ImageDimensions(width: 1200, height: 1800)
        let layoutDimensions = dimensions.scaledToFit(maxLongEdge: Self.maximumLayoutLongEdge)
        let imageReference = "../images/\(imageFileName)"
        let html = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head>
            <title>\(escapeXML(id))</title>
            <meta name="viewport" content="width=\(layoutDimensions.width), height=\(layoutDimensions.height)"/>
            <style type="text/css">
              html, body {
                margin: 0;
                padding: 0;
                width: \(layoutDimensions.width)px;
                height: \(layoutDimensions.height)px;
                overflow: hidden;
                background: #000;
              }
              body {
                width: \(layoutDimensions.width)px;
                height: \(layoutDimensions.height)px;
                line-height: 0;
              }
              svg {
                display: block;
                width: \(layoutDimensions.width)px;
                height: \(layoutDimensions.height)px;
              }
            </style>
          </head>
          <body>
            <svg class="mobi-verse-image"
                 xmlns="http://www.w3.org/2000/svg"
                 xmlns:xlink="http://www.w3.org/1999/xlink"
                 version="1.1"
                 width="\(layoutDimensions.width)"
                 height="\(layoutDimensions.height)"
                 viewBox="0 0 \(layoutDimensions.width) \(layoutDimensions.height)"
                 preserveAspectRatio="xMidYMid meet"
                 aria-label="Comic page">
              <image width="\(layoutDimensions.width)"
                     height="\(layoutDimensions.height)"
                     preserveAspectRatio="xMidYMid meet"
                     xlink:href="\(escapeXML(imageReference))"
                     href="\(escapeXML(imageReference))"/>
            </svg>
          </body>
        </html>
        """
        try html.write(
            to: pagesDirectory.appendingPathComponent(htmlFileName),
            atomically: true,
            encoding: .utf8
        )

        return RebuiltPage(
            id: id,
            htmlFileName: htmlFileName,
            imageFileName: imageFileName,
            imageMediaType: mediaType(for: copiedImageURL),
            layoutDimensions: layoutDimensions
        )
    }

    private func writeNavigation(title: String, pages: [RebuiltPage], in oebpsURL: URL) throws {
        let navItems = tocEntries(for: pages).map { page in
            """
                <li><a href="pages/\(page.htmlFileName)">\(escapeXML(page.id))</a></li>
            """
        }.joined(separator: "\n")
        let nav = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
          <head>
            <title>\(escapeXML(title))</title>
          </head>
          <body>
            <nav epub:type="toc" id="toc">
              <h1>\(escapeXML(title))</h1>
              <ol>
        \(navItems)
              </ol>
            </nav>
          </body>
        </html>
        """
        try nav.write(to: oebpsURL.appendingPathComponent("nav.xhtml"), atomically: true, encoding: .utf8)
    }

    private func writeContentOPF(title: String, pages: [RebuiltPage], in oebpsURL: URL) throws {
        let imageItems = pages.map { page in
            let coverProperty = page == pages.first ? #" properties="cover-image""# : ""
            return #"    <item id="\#(page.id)-image" href="images/\#(page.imageFileName)" media-type="\#(page.imageMediaType)"\#(coverProperty)/>"#
        }.joined(separator: "\n")
        let pageItems = pages.map { page in
            #"    <item id="\#(page.id)" href="pages/\#(page.htmlFileName)" media-type="application/xhtml+xml" properties="svg"/>"#
        }.joined(separator: "\n")
        let spineItems = pages.map { page in
            #"    <itemref idref="\#(page.id)" properties="rendition:layout-pre-paginated svg"/>"#
        }.joined(separator: "\n")
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf"
                 version="3.0"
                 unique-identifier="book-id"
                 prefix="rendition: http://www.idpf.org/vocab/rendition/#">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="book-id">urn:uuid:\(UUID().uuidString)</dc:identifier>
            <dc:title>\(escapeXML(title))</dc:title>
            <dc:language>ja</dc:language>
            <meta property="rendition:layout">pre-paginated</meta>
            <meta property="rendition:orientation">auto</meta>
            <meta property="rendition:spread">none</meta>
            <meta name="primary-writing-mode" content="vertical-rl"/>
            <meta name="fixed-layout" content="true"/>
            <meta name="book-type" content="comic"/>
            <meta name="zero-gutter" content="true"/>
            <meta name="zero-margin" content="true"/>
            <meta name="cover" content="page-00001-image"/>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        \(pageItems)
        \(imageItems)
          </manifest>
          <spine page-progression-direction="rtl">
        \(spineItems)
          </spine>
        </package>
        """
        try opf.write(to: oebpsURL.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)
    }

    private func rewriteStyles(in directory: URL) throws {
        let stylesheet = """
        html, body {
          margin: 0 !important;
          padding: 0 !important;
          width: 100% !important;
          height: 100% !important;
          min-height: 100% !important;
          background: #000 !important;
          overflow: hidden !important;
        }
        body, body.calibre, .calibre, .calibre1, .mobi-verse-page {
          display: flex !important;
          align-items: center !important;
          justify-content: center !important;
          margin: 0 !important;
          padding: 0 !important;
          text-align: center !important;
          text-indent: 0 !important;
          line-height: 0 !important;
          width: 100% !important;
          height: 100% !important;
          min-height: 100vh !important;
        }
        p {
          margin: 0 !important;
          padding: 0 !important;
        }
        img, .calibre2, .mobi-verse-image {
          display: block !important;
          width: auto !important;
          height: auto !important;
          max-width: 100% !important;
          max-height: 100% !important;
          margin: 0 auto !important;
          object-fit: contain !important;
          page-break-inside: avoid !important;
        }
        """
        try stylesheet.write(
            to: directory.appendingPathComponent("stylesheet.css"),
            atomically: true,
            encoding: .utf8
        )

        let pageStyles = """
        @page {
          margin: 0 !important;
          padding: 0 !important;
        }
        """
        try pageStyles.write(
            to: directory.appendingPathComponent("page_styles.css"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func normalizeLargeImages(_ imageFiles: [URL]) async throws {
        for imageURL in imageFiles {
            guard
                ["jpg", "jpeg", "png"].contains(imageURL.pathExtension.lowercased()),
                let dimensions = imageDimensions(at: imageURL),
                max(dimensions.width, dimensions.height) > Self.maximumImageLongEdge
            else {
                continue
            }

            let result = try await runner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/sips"),
                arguments: ["-Z", "\(Self.maximumImageLongEdge)", imageURL.path]
            )
            guard result.exitCode == 0 else {
                continue
            }
        }
    }

    private func rewriteImagePages(htmlFiles: [URL], rootDirectory: URL) throws -> Int {
        var rewrittenCount = 0
        for htmlURL in htmlFiles {
            guard
                let imageReference = try firstImageReference(in: htmlURL),
                let imageURL = resolvedURL(for: imageReference, from: htmlURL, rootDirectory: rootDirectory)
            else {
                continue
            }

            let dimensions = imageDimensions(at: imageURL) ?? ImageDimensions(width: 1200, height: 1800)
            let layoutDimensions = dimensions.scaledToFit(maxLongEdge: Self.maximumLayoutLongEdge)
            let title = escapeXML(htmlURL.deletingPathExtension().lastPathComponent)
            let imagePath = escapeXML(imageReference)
            let html = """
            <?xml version='1.0' encoding='utf-8'?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml">
              <head>
                <title>\(title)</title>
                <meta name="viewport" content="width=\(layoutDimensions.width), height=\(layoutDimensions.height)"/>
                <style type="text/css">
                  html, body {
                    margin: 0;
                    padding: 0;
                    width: \(layoutDimensions.width)px;
                    height: \(layoutDimensions.height)px;
                    overflow: hidden;
                    background: #000;
                  }
                  body.mobi-verse-page {
                    width: \(layoutDimensions.width)px;
                    height: \(layoutDimensions.height)px;
                    line-height: 0;
                    background-color: #000;
                  }
                  svg.mobi-verse-image {
                    display: block;
                    width: \(layoutDimensions.width)px;
                    height: \(layoutDimensions.height)px;
                    margin: 0;
                  }
                </style>
              </head>
              <body class="mobi-verse-page">
                <svg class="mobi-verse-image"
                     xmlns="http://www.w3.org/2000/svg"
                     xmlns:xlink="http://www.w3.org/1999/xlink"
                     version="1.1"
                     width="\(layoutDimensions.width)"
                     height="\(layoutDimensions.height)"
                     viewBox="0 0 \(layoutDimensions.width) \(layoutDimensions.height)"
                     preserveAspectRatio="xMidYMid meet"
                     aria-label="Comic page">
                  <image width="\(layoutDimensions.width)"
                         height="\(layoutDimensions.height)"
                         preserveAspectRatio="xMidYMid meet"
                         xlink:href="\(imagePath)"
                         href="\(imagePath)"/>
                </svg>
              </body>
            </html>
            """
            try html.write(to: htmlURL, atomically: true, encoding: .utf8)
            rewrittenCount += 1
        }
        return rewrittenCount
    }

    private func rewriteOPF(at url: URL) throws -> OPFRewriteResult {
        var opf = try String(contentsOf: url, encoding: .utf8)
        opf = rewritePackageTagForFixedLayout(opf)
        if opf.contains("primary-writing-mode") {
            opf = opf.replacingOccurrences(
                of: #"<meta name="primary-writing-mode" content="[^"]*"\s*/>"#,
                with: #"<meta name="primary-writing-mode" content="vertical-rl"/>"#,
                options: .regularExpression
            )
        } else {
            opf = opf.replacingOccurrences(
                of: "</metadata>",
                with: #"    <meta name="primary-writing-mode" content="vertical-rl"/>"# + "\n  </metadata>"
            )
        }

        if opf.contains("<spine toc=\"ncx\"") && !opf.contains("page-progression-direction=\"rtl\"") {
            opf = opf.replacingOccurrences(
                of: "<spine toc=\"ncx\"",
                with: "<spine toc=\"ncx\" page-progression-direction=\"rtl\""
            )
        }

        let fixedLayoutMetadata = [
            #"<meta property="rendition:layout">pre-paginated</meta>"#,
            #"<meta property="rendition:orientation">auto</meta>"#,
            #"<meta property="rendition:spread">none</meta>"#,
            #"<meta name="fixed-layout" content="true"/>"#,
            #"<meta name="book-type" content="comic"/>"#,
            #"<meta name="zero-gutter" content="true"/>"#,
            #"<meta name="zero-margin" content="true"/>"#
        ]
        for metadata in fixedLayoutMetadata where !opf.contains(metadata) {
            opf = opf.replacingOccurrences(
                of: "</metadata>",
                with: "    \(metadata)\n  </metadata>"
            )
        }
        opf = rewriteSpineItemrefsForFixedLayout(opf)

        try opf.write(to: url, atomically: true, encoding: .utf8)
        return OPFRewriteResult(
            appliedRightToLeftMetadata: opf.contains("vertical-rl") || opf.contains("page-progression-direction=\"rtl\""),
            appliedFixedLayoutMetadata: opf.contains("rendition:layout") && opf.contains("fixed-layout")
        )
    }

    private func rewritePackageTagForFixedLayout(_ opf: String) -> String {
        guard
            let regex = try? NSRegularExpression(pattern: #"<package\b([^>]*)>"#, options: []),
            let match = regex.firstMatch(in: opf, range: NSRange(opf.startIndex..<opf.endIndex, in: opf)),
            let matchRange = Range(match.range, in: opf)
        else {
            return opf
        }

        var packageTag = String(opf[matchRange])
        packageTag = packageTag.replacingOccurrences(
            of: #"version="[^"]*""#,
            with: #"version="3.0""#,
            options: .regularExpression
        )
        if !packageTag.contains("prefix=") {
            packageTag = packageTag.replacingOccurrences(
                of: ">",
                with: #" prefix="rendition: http://www.idpf.org/vocab/rendition/#">"#
            )
        } else if !packageTag.contains("http://www.idpf.org/vocab/rendition/#") {
            packageTag = packageTag.replacingOccurrences(
                of: #"prefix="([^"]*)""#,
                with: #"prefix="$1 rendition: http://www.idpf.org/vocab/rendition/#""#,
                options: .regularExpression
            )
        }

        var rewritten = opf
        rewritten.replaceSubrange(matchRange, with: packageTag)
        return rewritten
    }

    private func rewriteSpineItemrefsForFixedLayout(_ opf: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<itemref\b([^>]*)/>"#, options: []) else {
            return opf
        }
        let matches = regex.matches(in: opf, range: NSRange(opf.startIndex..<opf.endIndex, in: opf))
        var rewritten = opf
        for match in matches.reversed() {
            guard let range = Range(match.range, in: rewritten) else { continue }
            var itemref = String(rewritten[range])
            let requiredProperties = ["rendition:layout-pre-paginated", "svg"]
            if itemref.contains("properties=") {
                for property in requiredProperties where !itemref.contains(property) {
                    itemref = itemref.replacingOccurrences(
                        of: #"properties="([^"]*)""#,
                        with: #"properties="$1 \#(property)""#,
                        options: .regularExpression
                    )
                }
            } else {
                itemref = itemref.replacingOccurrences(
                    of: "/>",
                    with: #" properties="rendition:layout-pre-paginated svg"/>"#
                )
            }
            rewritten.replaceSubrange(range, with: itemref)
        }
        return rewritten
    }

    private func rewriteNCX(at url: URL, title: String, htmlFiles: [URL]) throws -> Int {
        let entries = tocEntries(for: htmlFiles)
        let navPoints = entries.enumerated().map { offset, htmlURL in
            let playOrder = offset + 1
            let label = offset == 0 ? "Start" : "Page \(playOrder)"
            return """
                <navPoint id="page-\(playOrder)" playOrder="\(playOrder)">
                  <navLabel>
                    <text>\(escapeXML(label))</text>
                  </navLabel>
                  <content src="text/\(htmlURL.lastPathComponent)"/>
                </navPoint>
            """
        }.joined(separator: "\n")

        let ncx = """
        <?xml version='1.0' encoding='utf-8'?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="jpn">
          <head>
            <meta name="dtb:depth" content="1"/>
            <meta name="dtb:generator" content="MobiVerse"/>
            <meta name="dtb:totalPageCount" content="0"/>
            <meta name="dtb:maxPageNumber" content="0"/>
          </head>
          <docTitle>
            <text>\(escapeXML(title))</text>
          </docTitle>
          <navMap>
        \(navPoints)
          </navMap>
        </ncx>
        """
        try ncx.write(to: url, atomically: true, encoding: .utf8)
        return entries.count
    }

    private func tocEntries(for htmlFiles: [URL]) -> [URL] {
        guard !htmlFiles.isEmpty else { return [] }
        var entries: [URL] = [htmlFiles[0]]
        for (index, htmlFile) in htmlFiles.enumerated() where index > 0 && index % 25 == 0 {
            entries.append(htmlFile)
        }
        return entries
    }

    private func tocEntries(for pages: [RebuiltPage]) -> [RebuiltPage] {
        guard !pages.isEmpty else { return [] }
        var entries: [RebuiltPage] = [pages[0]]
        for (index, page) in pages.enumerated() where index > 0 && index % 25 == 0 {
            entries.append(page)
        }
        return entries
    }

    private func sortedFiles(in directory: URL, extension pathExtension: String) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension.lowercased() == pathExtension }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func sortedHTMLFiles(in directory: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ["html", "xhtml", "htm"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func sortedImageFiles(in directory: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ["jpeg", "jpg", "png", "webp"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func discoveredImageFiles(in directory: URL) throws -> [URL] {
        let rootImages = try sortedImageFiles(in: directory.appendingPathComponent("images"))
        if !rootImages.isEmpty {
            return rootImages
        }

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { url in
                let path = url.path
                let pathExtension = url.pathExtension.lowercased()
                return ["jpeg", "jpg", "png", "webp"].contains(pathExtension)
                    && !path.contains("/__MACOSX/")
                    && !path.contains("/META-INF/")
            }
            .sorted { lhs, rhs in
                lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            }
    }

    private func packageDocumentURL(in directory: URL) -> URL {
        let containerURL = directory.appendingPathComponent("META-INF/container.xml")
        if
            let containerXML = try? String(contentsOf: containerURL, encoding: .utf8),
            let regex = try? NSRegularExpression(pattern: #"full-path=["']([^"']+)["']"#),
            let match = regex.firstMatch(in: containerXML, range: NSRange(containerXML.startIndex..<containerXML.endIndex, in: containerXML)),
            let range = Range(match.range(at: 1), in: containerXML)
        {
            if let packageURL = EpubPathSecurity.resolve(
                String(containerXML[range]),
                relativeTo: directory,
                containedIn: directory
            ) {
                return packageURL
            }
        }

        let candidates = [
            directory.appendingPathComponent("content.opf"),
            directory.appendingPathComponent("OEBPS/content.opf")
        ]
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
            ?? directory.appendingPathComponent("content.opf")
    }

    private func normalizedImageExtension(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        return pathExtension == "jpeg" ? "jpg" : pathExtension
    }

    private func mediaType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            "image/jpeg"
        case "png":
            "image/png"
        case "webp":
            "image/webp"
        default:
            "application/octet-stream"
        }
    }

    private func firstImageReference(in htmlURL: URL) throws -> String? {
        let html = try String(contentsOf: htmlURL, encoding: .utf8)
        let patterns = [
            #"<img[^>]+src=['"]([^'"]+)['"]"#,
            #"<image[^>]+(?:href|xlink:href)=['"]([^'"]+)['"]"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            guard
                let match = regex.firstMatch(in: html, range: range),
                let captureRange = Range(match.range(at: 1), in: html)
            else {
                continue
            }
            return html[captureRange]
                .replacingOccurrences(of: "&amp;", with: "&")
                .description
        }
        return nil
    }

    private func resolvedURL(for imageReference: String, from htmlURL: URL, rootDirectory: URL) -> URL? {
        let decodedReference = imageReference.removingPercentEncoding ?? imageReference
        if let directURL = EpubPathSecurity.resolve(
            decodedReference,
            relativeTo: htmlURL.deletingLastPathComponent(),
            containedIn: rootDirectory
        ), fileManager.fileExists(atPath: directURL.path) {
            return directURL
        }

        if let rootRelativeURL = EpubPathSecurity.resolve(
            decodedReference,
            relativeTo: rootDirectory,
            containedIn: rootDirectory
        ), fileManager.fileExists(atPath: rootRelativeURL.path) {
            return rootRelativeURL
        }

        return nil
    }

    private func imageDimensions(at url: URL) -> ImageDimensions? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        switch url.pathExtension.lowercased() {
        case "png":
            return pngDimensions(from: data)
        case "jpg", "jpeg":
            return jpegDimensions(from: data)
        default:
            return nil
        }
    }

    private func pngDimensions(from data: Data) -> ImageDimensions? {
        guard data.count >= 24 else { return nil }
        let signature = [UInt8](data.prefix(8))
        guard signature == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] else {
            return nil
        }
        let width = Int(data[16]) << 24 | Int(data[17]) << 16 | Int(data[18]) << 8 | Int(data[19])
        let height = Int(data[20]) << 24 | Int(data[21]) << 16 | Int(data[22]) << 8 | Int(data[23])
        return ImageDimensions(width: width, height: height)
    }

    private func jpegDimensions(from data: Data) -> ImageDimensions? {
        guard data.count > 4, data[0] == 0xFF, data[1] == 0xD8 else { return nil }
        var index = 2
        while index + 9 < data.count {
            guard data[index] == 0xFF else {
                index += 1
                continue
            }
            let marker = data[index + 1]
            index += 2
            if marker == 0xD9 || marker == 0xDA {
                break
            }
            guard index + 1 < data.count else { break }
            let segmentLength = Int(data[index]) << 8 | Int(data[index + 1])
            guard segmentLength >= 2, index + segmentLength <= data.count else { break }
            if (0xC0...0xC3).contains(marker) || (0xC5...0xC7).contains(marker) || (0xC9...0xCB).contains(marker) || (0xCD...0xCF).contains(marker) {
                guard index + 7 < data.count else { return nil }
                let height = Int(data[index + 3]) << 8 | Int(data[index + 4])
                let width = Int(data[index + 5]) << 8 | Int(data[index + 6])
                return ImageDimensions(width: width, height: height)
            }
            index += segmentLength
        }
        return nil
    }

    private func title(fromOPFAt url: URL) -> String? {
        guard let opf = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        guard let match = opf.range(of: #"<dc:title>(.*?)</dc:title>"#, options: .regularExpression) else {
            return nil
        }
        return String(opf[match])
            .replacingOccurrences(of: "<dc:title>", with: "")
            .replacingOccurrences(of: "</dc:title>", with: "")
    }

    private func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

public enum ComicPostProcessError: Error, Equatable {
    case unzipFailed(String)
    case zipFailed(String)
}
