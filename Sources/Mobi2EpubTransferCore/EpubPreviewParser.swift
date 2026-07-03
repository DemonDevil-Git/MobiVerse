import Foundation
import ImageIO

public enum EpubReadingDirection: String, Equatable, Sendable {
    case leftToRight
    case rightToLeft
}

public struct EpubImagePreviewPage: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let imageURL: URL
    public let width: Int
    public let height: Int
}

public enum EpubPreviewMode: Equatable, Sendable {
    case imagePages([EpubImagePreviewPage])
    case web(spineURLs: [URL])
}

public struct EpubPreviewBook: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let title: String
    public let epubURL: URL
    public let extractionDirectory: URL
    public let contentRootDirectory: URL
    public let readingDirection: EpubReadingDirection
    public let mode: EpubPreviewMode
}

public enum EpubPreviewParserError: Error, Equatable, Sendable {
    case unzipFailed(String)
    case missingPackageDocument
    case unreadablePackageDocument
    case missingReadableContent

    public var message: String {
        switch self {
        case .unzipFailed(let log):
            "Could not open EPUB archive. \(log)"
        case .missingPackageDocument:
            "The EPUB package document could not be found."
        case .unreadablePackageDocument:
            "The EPUB package document could not be read."
        case .missingReadableContent:
            "No readable pages were found in this EPUB."
        }
    }
}

public struct EpubPreviewParser {
    private let runner: any ProcessRunning
    private let fileManager: FileManager

    public init(runner: any ProcessRunning = ProcessRunner(), fileManager: FileManager = .default) {
        self.runner = runner
        self.fileManager = fileManager
    }

    public func parse(epubURL: URL, extractionDirectory: URL) async throws -> EpubPreviewBook {
        try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        let unzipResult = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-q", epubURL.path, "-d", extractionDirectory.path]
        )
        guard unzipResult.exitCode == 0 else {
            throw EpubPreviewParserError.unzipFailed(unzipResult.output)
        }

        let opfURL = try packageDocumentURL(in: extractionDirectory)
        guard let opf = try? String(contentsOf: opfURL, encoding: .utf8) else {
            throw EpubPreviewParserError.unreadablePackageDocument
        }

        let packageDirectory = opfURL.deletingLastPathComponent()
        let title = metadataTitle(from: opf) ?? epubURL.deletingPathExtension().lastPathComponent
        let manifest = manifestItems(from: opf)
        let spineIDs = spineItemIDs(from: opf)
        let direction = opf.contains(#"page-progression-direction="rtl""#) ? EpubReadingDirection.rightToLeft : .leftToRight

        let spineItems = spineIDs.compactMap { manifest[$0] }
        let imagePages = imagePreviewPages(from: spineItems, packageDirectory: packageDirectory)
        if imagePages.count >= 2, imagePages.count >= max(1, spineItems.count * 4 / 5) {
            return EpubPreviewBook(
                title: title,
                epubURL: epubURL,
                extractionDirectory: extractionDirectory,
                contentRootDirectory: packageDirectory,
                readingDirection: direction,
                mode: .imagePages(imagePages)
            )
        }

        let spineURLs = spineItems.compactMap { item -> URL? in
            guard item.mediaType.contains("xhtml") || item.mediaType.contains("html") else { return nil }
            return EpubPathSecurity.resolve(
                item.href,
                relativeTo: packageDirectory,
                containedIn: extractionDirectory
            )
        }
        if !spineURLs.isEmpty {
            return EpubPreviewBook(
                title: title,
                epubURL: epubURL,
                extractionDirectory: extractionDirectory,
                contentRootDirectory: packageDirectory,
                readingDirection: direction,
                mode: .web(spineURLs: spineURLs)
            )
        }

        throw EpubPreviewParserError.missingReadableContent
    }

    private func packageDocumentURL(in extractionDirectory: URL) throws -> URL {
        let containerURL = extractionDirectory.appendingPathComponent("META-INF/container.xml")
        if
            let containerXML = try? String(contentsOf: containerURL, encoding: .utf8),
            let fullPath = firstAttribute("full-path", inTagMatching: #"<rootfile\b[^>]*>"#, text: containerXML)
        {
            guard let packageURL = EpubPathSecurity.resolve(
                decodeXML(fullPath),
                relativeTo: extractionDirectory,
                containedIn: extractionDirectory
            ) else {
                throw EpubPreviewParserError.missingPackageDocument
            }
            return packageURL
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

    private func metadataTitle(from opf: String) -> String? {
        firstCapture(pattern: #"<dc:title[^>]*>(.*?)</dc:title>"#, text: opf)
            .map(decodeXML)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private func manifestItems(from opf: String) -> [String: ManifestItem] {
        tags(matching: #"<item\b[^>]*>"#, in: opf).reduce(into: [:]) { result, tag in
            guard
                let id = attribute("id", in: tag),
                let href = attribute("href", in: tag)
            else {
                return
            }
            result[id] = ManifestItem(
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

    private func imagePreviewPages(from spineItems: [ManifestItem], packageDirectory: URL) -> [EpubImagePreviewPage] {
        spineItems.enumerated().compactMap { index, item in
            guard let itemURL = EpubPathSecurity.resolve(
                item.href,
                relativeTo: packageDirectory,
                containedIn: packageDirectory
            ) else {
                return nil
            }
            let imageURL: URL?
            if item.mediaType.hasPrefix("image/") {
                imageURL = itemURL
            } else if item.mediaType.contains("xhtml") || item.mediaType.contains("html") {
                imageURL = imageURLReferencedByImageOnlyXHTML(at: itemURL)
            } else {
                imageURL = nil
            }

            guard let imageURL, fileManager.fileExists(atPath: imageURL.path) else {
                return nil
            }
            let dimensions = imageDimensions(at: imageURL) ?? (width: 1200, height: 1800)
            let pageNumber = index + 1
            return EpubImagePreviewPage(
                id: String(format: "page-%05d", pageNumber),
                title: "Page \(pageNumber)",
                imageURL: imageURL,
                width: dimensions.width,
                height: dimensions.height
            )
        }
    }

    private func imageURLReferencedByImageOnlyXHTML(at htmlURL: URL) -> URL? {
        guard let data = try? Data(contentsOf: htmlURL) else {
            return nil
        }
        let inspector = XHTMLImagePageInspector()
        let parser = XMLParser(data: data)
        parser.delegate = inspector
        guard parser.parse(), let reference = inspector.imageOnlyReference else {
            return nil
        }
        return EpubPathSecurity.resolve(
            decodeXML(reference),
            relativeTo: htmlURL.deletingLastPathComponent(),
            containedIn: packageRoot(for: htmlURL)
        )
    }

    private func packageRoot(for url: URL) -> URL {
        var current = url.deletingLastPathComponent()
        while current.pathComponents.count > 1 {
            if fileManager.fileExists(atPath: current.appendingPathComponent("content.opf").path) {
                return current
            }
            current.deleteLastPathComponent()
        }
        return url.deletingLastPathComponent()
    }

    private func imageDimensions(at url: URL) -> (width: Int, height: Int)? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        return (width, height)
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

private final class XHTMLImagePageInspector: NSObject, XMLParserDelegate {
    private var ignoredElementDepth = 0
    private var imageReferences: [String] = []
    private var visibleText = ""

    var imageOnlyReference: String? {
        guard
            imageReferences.count == 1,
            visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !imageReferences[0].hasPrefix("data:")
        else {
            return nil
        }
        return imageReferences[0]
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if ignoredElementDepth > 0 {
            ignoredElementDepth += 1
            return
        }

        let name = localName(qName ?? elementName)
        if ["head", "script", "style"].contains(name) {
            ignoredElementDepth = 1
            return
        }

        guard name == "img" || name == "image" else { return }
        let reference = attributeDict.first { key, _ in
            let attributeName = localName(key)
            return attributeName == "src" || attributeName == "href"
        }?.value
        if let reference {
            imageReferences.append(reference)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if ignoredElementDepth > 0 {
            ignoredElementDepth -= 1
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard ignoredElementDepth == 0 else { return }
        visibleText.append(string)
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init)?.lowercased() ?? name.lowercased()
    }
}
