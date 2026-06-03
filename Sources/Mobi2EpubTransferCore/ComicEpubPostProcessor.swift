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

        let htmlFiles = try sortedHTMLFiles(in: workingDirectory.appendingPathComponent("text"))
        let imageFiles = try sortedImageFiles(in: workingDirectory.appendingPathComponent("images"))
        try await normalizeLargeImages(imageFiles)
        try rewriteStyles(in: workingDirectory)
        let rewrittenPageCount = try rewriteImagePages(htmlFiles: htmlFiles, rootDirectory: workingDirectory)
        let opfURL = workingDirectory.appendingPathComponent("content.opf")
        let opfResult = try rewriteOPF(at: opfURL)
        let tocEntryCount = try rewriteNCX(
            at: workingDirectory.appendingPathComponent("toc.ncx"),
            title: title(fromOPFAt: opfURL) ?? epubURL.deletingPathExtension().lastPathComponent,
            htmlFiles: htmlFiles
        )

        let replacementURL = epubURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(epubURL.deletingPathExtension().lastPathComponent)-postprocessed.epub")
        try? fileManager.removeItem(at: replacementURL)
        try? fileManager.removeItem(at: epubURL)

        let zipResult = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-X", "-q", "-r", replacementURL.path, "."],
            currentDirectoryURL: workingDirectory
        )
        guard zipResult.exitCode == 0 else {
            throw ComicPostProcessError.zipFailed(zipResult.output)
        }
        try fileManager.moveItem(at: replacementURL, to: epubURL)

        return ComicPostProcessResult(
            pageCount: htmlFiles.count,
            imageCount: imageFiles.count,
            tocEntryCount: tocEntryCount,
            removedFixedImageSizing: true,
            appliedRightToLeftMetadata: opfResult.appliedRightToLeftMetadata,
            appliedFixedLayoutMetadata: opfResult.appliedFixedLayoutMetadata && rewrittenPageCount > 0
        )
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
                    width: 100%;
                    height: 100%;
                    overflow: hidden;
                    background: #000;
                  }
                  body.mobi-verse-page {
                    width: 100%;
                    height: 100%;
                    min-height: 100vh;
                    line-height: 0;
                    background-color: #000;
                    background-image: url("\(imagePath)");
                    background-position: center center;
                    background-repeat: no-repeat;
                    background-size: contain;
                  }
                </style>
                <link href="../stylesheet.css" rel="stylesheet" type="text/css"/>
                <link href="../page_styles.css" rel="stylesheet" type="text/css"/>
              </head>
              <body class="mobi-verse-page">
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

        try opf.write(to: url, atomically: true, encoding: .utf8)
        return OPFRewriteResult(
            appliedRightToLeftMetadata: opf.contains("vertical-rl") || opf.contains("page-progression-direction=\"rtl\""),
            appliedFixedLayoutMetadata: opf.contains("rendition:layout") && opf.contains("fixed-layout")
        )
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
        let directURL = htmlURL
            .deletingLastPathComponent()
            .appendingPathComponent(decodedReference)
            .standardizedFileURL
        if fileManager.fileExists(atPath: directURL.path) {
            return directURL
        }

        let rootRelativeURL = rootDirectory
            .appendingPathComponent(decodedReference)
            .standardizedFileURL
        if fileManager.fileExists(atPath: rootRelativeURL.path) {
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
