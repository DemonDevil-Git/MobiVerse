import Foundation

public struct ComicPostProcessResult: Equatable, Sendable {
    public let pageCount: Int
    public let imageCount: Int
    public let tocEntryCount: Int
    public let removedFixedImageSizing: Bool
    public let appliedRightToLeftMetadata: Bool

    public var reportText: String {
        """
        Comic EPUB post-processing
        --------------------------
        Image pages: \(pageCount)
        Images: \(imageCount)
        TOC entries: \(tocEntryCount)
        Full-page responsive image CSS: \(removedFixedImageSizing ? "applied" : "not applied")
        Right-to-left manga metadata: \(appliedRightToLeftMetadata ? "applied" : "not applied")
        """
    }
}

public struct ComicEpubPostProcessor {
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

        let htmlFiles = try sortedFiles(in: workingDirectory.appendingPathComponent("text"), extension: "html")
        let imageFiles = try sortedFiles(in: workingDirectory.appendingPathComponent("images"), extension: "jpeg")
        try rewriteStyles(in: workingDirectory)
        let opfURL = workingDirectory.appendingPathComponent("content.opf")
        let appliedRTL = try rewriteOPF(at: opfURL)
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
            appliedRightToLeftMetadata: appliedRTL
        )
    }

    private func rewriteStyles(in directory: URL) throws {
        let stylesheet = """
        html, body {
          margin: 0 !important;
          padding: 0 !important;
          width: 100% !important;
          min-height: 100% !important;
          background: #000 !important;
        }
        body.calibre, .calibre, .calibre1 {
          display: block !important;
          margin: 0 !important;
          padding: 0 !important;
          text-align: center !important;
          text-indent: 0 !important;
          line-height: 0 !important;
        }
        p {
          margin: 0 !important;
          padding: 0 !important;
        }
        img, .calibre2 {
          display: block !important;
          width: auto !important;
          height: auto !important;
          max-width: 100% !important;
          max-height: 100vh !important;
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

    private func rewriteOPF(at url: URL) throws -> Bool {
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

        try opf.write(to: url, atomically: true, encoding: .utf8)
        return opf.contains("vertical-rl") || opf.contains("page-progression-direction=\"rtl\"")
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
