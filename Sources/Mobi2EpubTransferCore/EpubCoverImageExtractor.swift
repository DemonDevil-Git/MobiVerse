import Foundation

public struct EpubCoverImageExtractor {
    private let runner: any ProcessRunning
    private let fileManager: FileManager

    public init(runner: any ProcessRunning = ProcessRunner(), fileManager: FileManager = .default) {
        self.runner = runner
        self.fileManager = fileManager
    }

    public func coverImageURL(epubURL: URL, extractionDirectory: URL) async throws -> URL? {
        if fileManager.fileExists(atPath: extractionDirectory.path) {
            try fileManager.removeItem(at: extractionDirectory)
        }
        try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)

        let unzipResult = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-q", epubURL.path, "-d", extractionDirectory.path]
        )
        guard unzipResult.exitCode == 0 else {
            return nil
        }

        let opfURL = try packageDocumentURL(in: extractionDirectory)
        guard let opf = try? String(contentsOf: opfURL, encoding: .utf8) else {
            return nil
        }

        let packageDirectory = opfURL.deletingLastPathComponent()
        let manifest = manifestItems(from: opf)
        let manifestByID = Dictionary(uniqueKeysWithValues: manifest.map { ($0.id, $0) })

        if
            let coverID = metadataCoverID(from: opf),
            let coverURL = imageURL(for: manifestByID[coverID], packageDirectory: packageDirectory)
        {
            return coverURL
        }

        if
            let coverItem = manifest.first(where: { $0.properties.split(separator: " ").contains("cover-image") }),
            let coverURL = imageURL(for: coverItem, packageDirectory: packageDirectory)
        {
            return coverURL
        }

        let spineItems = spineItemIDs(from: opf).compactMap { manifestByID[$0] }
        if let firstSpineImageURL = spineItems.lazy.compactMap({ imageURL(for: $0, packageDirectory: packageDirectory) }).first {
            return firstSpineImageURL
        }

        return manifest.lazy.compactMap { imageURL(for: $0, packageDirectory: packageDirectory) }.first
    }

    private func imageURL(for item: ManifestItem?, packageDirectory: URL) -> URL? {
        guard let item else { return nil }
        let itemURL = packageDirectory.appendingPathComponent(item.href).standardizedFileURL
        let imageURL: URL?

        if item.mediaType.hasPrefix("image/") {
            imageURL = itemURL
        } else if item.mediaType.contains("xhtml") || item.mediaType.contains("html") {
            imageURL = imageURLReferencedByXHTML(at: itemURL)
        } else {
            imageURL = nil
        }

        guard let imageURL, fileManager.fileExists(atPath: imageURL.path) else {
            return nil
        }
        return imageURL
    }

    private func packageDocumentURL(in extractionDirectory: URL) throws -> URL {
        let containerURL = extractionDirectory.appendingPathComponent("META-INF/container.xml")
        if
            let containerXML = try? String(contentsOf: containerURL, encoding: .utf8),
            let fullPath = firstAttribute("full-path", inTagMatching: #"<rootfile\b[^>]*>"#, text: containerXML)
        {
            return extractionDirectory.appendingPathComponent(fullPath).standardizedFileURL
        }

        let candidates = [
            extractionDirectory.appendingPathComponent("content.opf"),
            extractionDirectory.appendingPathComponent("OEBPS/content.opf")
        ]
        if let candidate = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            return candidate
        }
        throw EpubPreviewParserError.missingPackageDocument
    }

    private func metadataCoverID(from opf: String) -> String? {
        firstCapture(pattern: #"<meta\b[^>]*name\s*=\s*["']cover["'][^>]*content\s*=\s*["']([^"']+)["'][^>]*/?>"#, text: opf)
            ?? firstCapture(pattern: #"<meta\b[^>]*content\s*=\s*["']([^"']+)["'][^>]*name\s*=\s*["']cover["'][^>]*/?>"#, text: opf)
    }

    private func manifestItems(from opf: String) -> [ManifestItem] {
        tags(matching: #"<item\b[^>]*>"#, in: opf).compactMap { tag in
            guard
                let id = attribute("id", in: tag),
                let href = attribute("href", in: tag)
            else {
                return nil
            }
            return ManifestItem(
                id: id,
                href: decodeXML(href),
                mediaType: attribute("media-type", in: tag) ?? "",
                properties: attribute("properties", in: tag) ?? ""
            )
        }
    }

    private func spineItemIDs(from opf: String) -> [String] {
        tags(matching: #"<itemref\b[^>]*>"#, in: opf).compactMap { attribute("idref", in: $0) }
    }

    private func imageURLReferencedByXHTML(at htmlURL: URL) -> URL? {
        guard let html = try? String(contentsOf: htmlURL, encoding: .utf8) else {
            return nil
        }
        let patterns = [
            #"<img\b[^>]*(?:src|href)=["']([^"']+)["'][^>]*>"#,
            #"<image\b[^>]*(?:xlink:href|href)=["']([^"']+)["'][^>]*>"#,
            #"(?:src|href)=["']([^"']+\.(?:jpg|jpeg|png|gif|webp|svg))["']"#
        ]
        guard
            let reference = patterns.lazy.compactMap({ firstCapture(pattern: $0, text: html) }).first,
            !reference.hasPrefix("data:")
        else {
            return nil
        }
        return htmlURL
            .deletingLastPathComponent()
            .appendingPathComponent(decodeXML(reference))
            .standardizedFileURL
    }

    private func tags(matching pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        return regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private func firstAttribute(_ name: String, inTagMatching pattern: String, text: String) -> String? {
        tags(matching: pattern, in: text).compactMap { attribute(name, in: $0) }.first
    }

    private func attribute(_ name: String, in tag: String) -> String? {
        firstCapture(pattern: #"\b\#(name)\s*=\s*["']([^"']*)["']"#, text: tag)
    }

    private func firstCapture(pattern: String, text: String) -> String? {
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[range])
    }

    private func decodeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}

private struct ManifestItem: Equatable {
    let id: String
    let href: String
    let mediaType: String
    let properties: String
}
