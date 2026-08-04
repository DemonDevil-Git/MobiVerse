import Foundation

public struct EpubCoverImageExtractor {
    private let runner: any ProcessRunning
    private let fileManager: FileManager

    public init(runner: any ProcessRunning = ProcessRunner(), fileManager: FileManager = .default) {
        self.runner = runner
        self.fileManager = fileManager
    }

    /// Extracts only the package documents and selected cover entry. Large comic
    /// EPUBs can contain hundreds of pages, so expanding the whole archive here
    /// would compete with shelf animations for disk and CPU time.
    public func coverImageURL(epubURL: URL, extractionDirectory: URL) async throws -> URL? {
        if fileManager.fileExists(atPath: extractionDirectory.path) {
            try fileManager.removeItem(at: extractionDirectory)
        }
        try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)

        let listing = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-Z1", epubURL.path]
        )
        guard listing.exitCode == 0 else { return nil }
        let archivePaths = listing.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter(isSafeArchivePath)
        guard !archivePaths.isEmpty else { return nil }

        let packagePath = try await packageDocumentPath(in: epubURL, archivePaths: archivePaths)
        guard
            let packagePath,
            let packageDocument = try await archiveText(
                at: packagePath,
                epubURL: epubURL
            )
        else {
            return nil
        }

        let manifest = manifestItems(from: packageDocument)
        let manifestByID = Dictionary(uniqueKeysWithValues: manifest.map { ($0.id, $0) })
        var candidates: [ManifestItem] = []

        if let coverID = metadataCoverID(from: packageDocument), let item = manifestByID[coverID] {
            candidates.append(item)
        }
        if let item = manifest.first(where: { $0.properties.split(separator: " ").contains("cover-image") }) {
            candidates.append(item)
        }
        candidates.append(contentsOf: spineItemIDs(from: packageDocument).compactMap { manifestByID[$0] })
        candidates.append(contentsOf: manifest)

        var attemptedItems: Set<String> = []
        for item in candidates where attemptedItems.insert(item.id).inserted {
            guard let imagePath = try await imageArchivePath(
                for: item,
                packagePath: packagePath,
                archivePaths: archivePaths,
                epubURL: epubURL
            ) else {
                continue
            }
            if let extractedURL = try await extractArchiveEntry(
                imagePath,
                epubURL: epubURL,
                to: extractionDirectory
            ) {
                return extractedURL
            }
        }
        return nil
    }

    private func packageDocumentPath(in epubURL: URL, archivePaths: [String]) async throws -> String? {
        if let containerPath = exactArchivePath("META-INF/container.xml", in: archivePaths),
           let container = try await archiveText(at: containerPath, epubURL: epubURL),
           let referencedPath = firstAttribute(
               "full-path",
               inTagMatching: #"<rootfile\b[^>]*>"#,
               text: container
           ),
           let resolved = exactArchivePath(decodeXML(referencedPath), in: archivePaths) {
            return resolved
        }

        for fallback in ["content.opf", "OEBPS/content.opf"] {
            if let resolved = exactArchivePath(fallback, in: archivePaths) { return resolved }
        }
        return archivePaths.first { $0.lowercased().hasSuffix(".opf") }
    }

    private func imageArchivePath(
        for item: ManifestItem,
        packagePath: String,
        archivePaths: [String],
        epubURL: URL
    ) async throws -> String? {
        let packageDirectory = archiveDirectory(of: packagePath)
        guard let itemPath = resolveArchivePath(
            item.href,
            relativeTo: packageDirectory,
            archivePaths: archivePaths
        ) else {
            return nil
        }

        if item.mediaType.hasPrefix("image/") {
            return itemPath
        }
        guard item.mediaType.contains("xhtml") || item.mediaType.contains("html") else { return nil }
        guard
            let html = try await archiveText(at: itemPath, epubURL: epubURL),
            let reference = imageReference(from: html)
        else {
            return nil
        }
        return resolveArchivePath(
            reference,
            relativeTo: archiveDirectory(of: itemPath),
            archivePaths: archivePaths
        )
    }

    private func archiveText(at path: String, epubURL: URL) async throws -> String? {
        guard isSafeArchivePath(path) else { return nil }
        let result = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-p", epubURL.path, path]
        )
        return result.exitCode == 0 ? result.output : nil
    }

    private func extractArchiveEntry(_ path: String, epubURL: URL, to directory: URL) async throws -> URL? {
        guard isSafeArchivePath(path) else { return nil }
        let result = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-j", "-q", epubURL.path, path, "-d", directory.path]
        )
        guard result.exitCode == 0 else { return nil }
        let outputURL = directory.appendingPathComponent((path as NSString).lastPathComponent)
        return fileManager.fileExists(atPath: outputURL.path) ? outputURL : nil
    }

    private func resolveArchivePath(
        _ reference: String,
        relativeTo directory: String,
        archivePaths: [String]
    ) -> String? {
        let decoded = decodeXML(reference).removingPercentEncoding ?? decodeXML(reference)
        let pathOnly = decoded.components(separatedBy: CharacterSet(charactersIn: "#?")).first ?? decoded
        guard !pathOnly.isEmpty, !pathOnly.hasPrefix("/"), URL(string: pathOnly)?.scheme == nil else { return nil }

        // Resolve EPUB-relative links inside a virtual root. NSString's relative
        // path normalization leaves some leading `..` segments untouched, which
        // breaks the common `pages/cover.xhtml -> ../images/cover.jpg` layout.
        let virtualRoot = URL(fileURLWithPath: "/MobiVerseEPUBRoot", isDirectory: true)
        let baseURL = directory.isEmpty
            ? virtualRoot
            : virtualRoot.appendingPathComponent(directory, isDirectory: true)
        let resolvedURL = URL(fileURLWithPath: pathOnly, relativeTo: baseURL).standardizedFileURL
        let rootPrefix = virtualRoot.path + "/"
        guard resolvedURL.path.hasPrefix(rootPrefix) else { return nil }

        let normalized = String(resolvedURL.path.dropFirst(rootPrefix.count))
        guard isSafeArchivePath(normalized) else { return nil }
        return exactArchivePath(normalized, in: archivePaths)
    }

    private func archiveDirectory(of path: String) -> String {
        let directory = (path as NSString).deletingLastPathComponent
        return directory == "." ? "" : directory
    }

    private func exactArchivePath(_ candidate: String, in archivePaths: [String]) -> String? {
        let normalizedCandidate = candidate.replacingOccurrences(of: "\\", with: "/")
        guard isSafeArchivePath(normalizedCandidate) else { return nil }
        return archivePaths.first { $0.caseInsensitiveCompare(normalizedCandidate) == .orderedSame }
    }

    private func isSafeArchivePath(_ path: String) -> Bool {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.isEmpty, !normalized.hasPrefix("/") else { return false }
        return !normalized.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    private func metadataCoverID(from opf: String) -> String? {
        firstCapture(pattern: #"<meta\b[^>]*name\s*=\s*[\"']cover[\"'][^>]*content\s*=\s*[\"']([^\"']+)[\"'][^>]*/?>"#, text: opf)
            ?? firstCapture(pattern: #"<meta\b[^>]*content\s*=\s*[\"']([^\"']+)[\"'][^>]*name\s*=\s*[\"']cover[\"'][^>]*/?>"#, text: opf)
    }

    private func manifestItems(from opf: String) -> [ManifestItem] {
        tags(matching: #"<item\b[^>]*>"#, in: opf).compactMap { tag in
            guard let id = attribute("id", in: tag), let href = attribute("href", in: tag) else { return nil }
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

    private func imageReference(from html: String) -> String? {
        let patterns = [
            #"<img\b[^>]*(?:src|href)=[\"']([^\"']+)[\"'][^>]*>"#,
            #"<image\b[^>]*(?:xlink:href|href)=[\"']([^\"']+)[\"'][^>]*>"#,
            #"(?:src|href)=[\"']([^\"']+\.(?:jpg|jpeg|png|gif|webp|svg))[\"']"#
        ]
        return patterns.lazy
            .compactMap { firstCapture(pattern: $0, text: html) }
            .first { !$0.lowercased().hasPrefix("data:") }
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
        firstCapture(pattern: #"\b\#(name)\s*=\s*[\"']([^\"']*)[\"']"#, text: tag)
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
