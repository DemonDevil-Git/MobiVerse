import Foundation

public struct EpubBookMetadata: Codable, Equatable, Sendable {
    public let title: String
    public let creators: [String]
    public let publisher: String?
    public let language: String?
    public let description: String?
    public let subjects: [String]

    public init(
        title: String,
        creators: [String] = [],
        publisher: String? = nil,
        language: String? = nil,
        description: String? = nil,
        subjects: [String] = []
    ) {
        self.title = title
        self.creators = creators
        self.publisher = publisher
        self.language = language
        self.description = description
        self.subjects = subjects
    }

    public var creatorLine: String {
        creators.joined(separator: ", ")
    }
}

public struct EpubMetadataExtractor {
    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning = ProcessRunner()) {
        self.runner = runner
    }

    public func metadata(epubURL: URL) async throws -> EpubBookMetadata? {
        let archiveListing = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-Z1", epubURL.path]
        )
        guard archiveListing.exitCode == 0 else { return nil }
        let archivePaths = archiveListing.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        let containerPath = archivePaths.first { $0.caseInsensitiveCompare("META-INF/container.xml") == .orderedSame }
        var packagePath: String?
        if let containerPath, isSafeArchivePath(containerPath) {
            let container = try await runner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
                arguments: ["-p", epubURL.path, containerPath]
            )
            if container.exitCode == 0 {
                packagePath = firstCapture(
                    pattern: #"<rootfile\b[^>]*\bfull-path\s*=\s*[\"']([^\"']+)[\"']"#,
                    text: container.output
                )
            }
        }

        if packagePath == nil {
            packagePath = archivePaths.first { $0.lowercased().hasSuffix(".opf") }
        }
        guard let packagePath, isSafeArchivePath(packagePath) else { return nil }

        let packageDocument = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-p", epubURL.path, packagePath]
        )
        guard packageDocument.exitCode == 0 else { return nil }

        let parserDelegate = OPFMetadataParser()
        let parser = XMLParser(data: Data(packageDocument.output.utf8))
        parser.delegate = parserDelegate
        guard parser.parse() else { return nil }
        return parserDelegate.metadata(fallbackTitle: epubURL.deletingPathExtension().lastPathComponent)
    }

    private func isSafeArchivePath(_ path: String) -> Bool {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.isEmpty, !normalized.hasPrefix("/") else { return false }
        return !normalized.split(separator: "/", omittingEmptySubsequences: false).contains("..")
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
}

private final class OPFMetadataParser: NSObject, XMLParserDelegate {
    private var metadataDepth: Int?
    private var elementDepth = 0
    private var capture: (name: String, depth: Int, text: String)?
    private var values: [String: [String]] = [:]

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        elementDepth += 1
        let name = localName(qName ?? elementName)
        if name == "metadata" {
            metadataDepth = elementDepth
            return
        }
        guard metadataDepth != nil, capture == nil, Self.supportedElements.contains(name) else { return }
        capture = (name, elementDepth, "")
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(qName ?? elementName)
        if let current = capture, current.name == name, current.depth == elementDepth {
            let normalized = normalize(current.text)
            if !normalized.isEmpty { values[current.name, default: []].append(normalized) }
            capture = nil
        }
        if name == "metadata", metadataDepth == elementDepth { metadataDepth = nil }
        elementDepth -= 1
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard var current = capture else { return }
        current.text.append(string)
        capture = current
    }

    func metadata(fallbackTitle: String) -> EpubBookMetadata {
        EpubBookMetadata(
            title: values["title"]?.first ?? fallbackTitle,
            creators: unique(values["creator"] ?? []),
            publisher: values["publisher"]?.first,
            language: values["language"]?.first,
            description: values["description"]?.first,
            subjects: unique(values["subject"] ?? [])
        )
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init)?.lowercased() ?? name.lowercased()
    }

    private func normalize(_ value: String) -> String {
        let withoutMarkup = value.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let decoded = withoutMarkup
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
        return decoded
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static let supportedElements: Set<String> = [
        "title", "creator", "publisher", "language", "description", "subject"
    ]
}
