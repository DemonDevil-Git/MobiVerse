import Foundation

public struct TextEpubPostProcessResult: Equatable, Sendable {
    public let repairedIdentifierCount: Int
    public let removedBrokenResourceCount: Int
    public let reorderedNavigationCount: Int

    public var reportText: String {
        """
        Text EPUB post-processing
        -------------------------
        EPUB 3 semantic markup preserved: yes
        Invalid identifiers repaired: \(repairedIdentifierCount)
        Broken style/resource references removed: \(removedBrokenResourceCount)
        Navigation playOrder values repaired: \(reorderedNavigationCount)
        """
    }
}

public enum TextEpubPostProcessError: Error, Equatable {
    case unzipFailed(String)
    case zipFailed(String)
}

/// Repairs structural defects commonly carried from KF8/AZW3 sources without
/// rewriting book text or removing semantic elements such as `<ruby>`.
public struct TextEpubPostProcessor: Sendable {
    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning = ProcessRunner()) {
        self.runner = runner
    }

    public func process(epubURL: URL) async throws -> TextEpubPostProcessResult {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("MobiVerseTextEpubRepair", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let extracted = workspace.appendingPathComponent("book", isDirectory: true)
        try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let unzip = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-qq", epubURL.path, "-d", extracted.path]
        )
        guard unzip.exitCode == 0 else { throw TextEpubPostProcessError.unzipFailed(unzip.output) }

        let contentFiles = regularFiles(in: extracted)
        let repairedIdentifiers = try repairInvalidIdentifiers(in: contentFiles)
        let removedResources = try removeBrokenResourceReferences(in: contentFiles, root: extracted)
        let reorderedNavigation = try repairNavigationOrder(in: contentFiles)

        guard repairedIdentifiers + removedResources + reorderedNavigation > 0 else {
            return TextEpubPostProcessResult(
                repairedIdentifierCount: 0,
                removedBrokenResourceCount: 0,
                reorderedNavigationCount: 0
            )
        }

        let rebuiltURL = epubURL.deletingLastPathComponent()
            .appendingPathComponent(".mobiverse-text-repair-\(UUID().uuidString).epub")
        defer { try? fileManager.removeItem(at: rebuiltURL) }

        let mimetypeURL = extracted.appendingPathComponent("mimetype")
        if fileManager.fileExists(atPath: mimetypeURL.path) {
            let mimetypeZip = try await runner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
                arguments: ["-X0q", rebuiltURL.path, "mimetype"],
                currentDirectoryURL: extracted
            )
            guard mimetypeZip.exitCode == 0 else { throw TextEpubPostProcessError.zipFailed(mimetypeZip.output) }
        }

        let rootEntries = try fileManager.contentsOfDirectory(atPath: extracted.path)
            .filter { $0 != "mimetype" }
            .sorted()
        if !rootEntries.isEmpty {
            let contentZip = try await runner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
                arguments: ["-Xr9qD", rebuiltURL.path] + rootEntries,
                currentDirectoryURL: extracted
            )
            guard contentZip.exitCode == 0 else { throw TextEpubPostProcessError.zipFailed(contentZip.output) }
        }

        _ = try fileManager.replaceItemAt(epubURL, withItemAt: rebuiltURL)
        return TextEpubPostProcessResult(
            repairedIdentifierCount: repairedIdentifiers,
            removedBrokenResourceCount: removedResources,
            reorderedNavigationCount: reorderedNavigation
        )
    }

    private func regularFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            return url
        }
    }

    private func repairInvalidIdentifiers(in files: [URL]) throws -> Int {
        let extensions = Set(["xhtml", "html", "htm", "xml", "opf", "ncx"])
        let idRegex = try NSRegularExpression(pattern: #"\bid\s*=\s*([\"'])([^\"']+)\1"#, options: [.caseInsensitive])
        var mapping: [String: String] = [:]
        var used = Set<String>()

        for file in files where extensions.contains(file.pathExtension.lowercased()) {
            let text = try String(contentsOf: file, encoding: .utf8)
            let nsText = text as NSString
            for match in idRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
                let identifier = nsText.substring(with: match.range(at: 2))
                used.insert(identifier)
                guard !isValidXMLIdentifier(identifier), mapping[identifier] == nil else { continue }
                var replacement = sanitizedIdentifier(identifier)
                var suffix = 2
                while used.contains(replacement) {
                    replacement = "\(sanitizedIdentifier(identifier))-\(suffix)"
                    suffix += 1
                }
                mapping[identifier] = replacement
                used.insert(replacement)
            }
        }

        guard !mapping.isEmpty else { return 0 }
        for file in files where extensions.contains(file.pathExtension.lowercased()) {
            var text = try String(contentsOf: file, encoding: .utf8)
            let original = text
            for (invalid, valid) in mapping {
                let escaped = NSRegularExpression.escapedPattern(for: invalid)
                text = text.replacingOccurrences(
                    of: #"(\bid\s*=\s*[\"'])"# + escaped + #"([\"'])"#,
                    with: "$1\(valid)$2",
                    options: [.regularExpression, .caseInsensitive]
                )
                text = text.replacingOccurrences(of: "#\(invalid)", with: "#\(valid)")
            }
            if text != original { try text.write(to: file, atomically: true, encoding: .utf8) }
        }
        return mapping.count
    }

    private func removeBrokenResourceReferences(in files: [URL], root: URL) throws -> Int {
        var removedCount = 0
        for file in files where file.pathExtension.lowercased() == "css" {
            var css = try String(contentsOf: file, encoding: .utf8)
            let original = css
            let fontFaceRegex = try NSRegularExpression(
                pattern: #"@font-face\s*\{.*?\}"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
            let nsCSS = css as NSString
            let blocks = fontFaceRegex.matches(in: css, range: NSRange(location: 0, length: nsCSS.length))
                .map { nsCSS.substring(with: $0.range) }
            for block in blocks where containsMissingURL(in: block, relativeTo: file, root: root) {
                css = css.replacingOccurrences(of: block, with: "")
                removedCount += 1
            }

            let missingURLs = missingURLTokens(in: css, relativeTo: file, root: root)
            for token in missingURLs {
                let escaped = NSRegularExpression.escapedPattern(for: token)
                let declaration = #"(?im)^\s*[-a-z0-9_]+\s*:\s*[^;{}]*"# + escaped + #"[^;{}]*;\s*"#
                let before = css
                css = css.replacingOccurrences(of: declaration, with: "", options: .regularExpression)
                if css != before { removedCount += 1 }
            }
            if css != original { try css.write(to: file, atomically: true, encoding: .utf8) }
        }

        let markupExtensions = Set(["xhtml", "html", "htm"])
        for file in files where markupExtensions.contains(file.pathExtension.lowercased()) {
            var markup = try String(contentsOf: file, encoding: .utf8)
            let original = markup
            let linkRegex = try NSRegularExpression(pattern: #"<link\b[^>]*>"#, options: [.caseInsensitive])
            let nsMarkup = markup as NSString
            let links = linkRegex.matches(in: markup, range: NSRange(location: 0, length: nsMarkup.length))
                .map { nsMarkup.substring(with: $0.range) }
            for link in links where link.range(of: "stylesheet", options: .caseInsensitive) != nil {
                guard let href = attribute(named: "href", in: link),
                      isMissingLocalResource(href, relativeTo: file, root: root) else { continue }
                markup = markup.replacingOccurrences(of: link, with: "")
                removedCount += 1
            }
            if markup != original { try markup.write(to: file, atomically: true, encoding: .utf8) }
        }
        return removedCount
    }

    private func repairNavigationOrder(in files: [URL]) throws -> Int {
        let playOrderRegex = try NSRegularExpression(pattern: #"playOrder\s*=\s*([\"'])\d+\1"#, options: [.caseInsensitive])
        var repaired = 0
        for file in files where file.pathExtension.lowercased() == "ncx" {
            var text = try String(contentsOf: file, encoding: .utf8)
            let nsText = text as NSString
            let matches = playOrderRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            guard !matches.isEmpty else { continue }
            for (offset, match) in matches.enumerated().reversed() {
                let oldValue = nsText.substring(with: match.range)
                let quote = oldValue.contains("\"") ? "\"" : "'"
                let expected = "playOrder=\(quote)\(offset + 1)\(quote)"
                if oldValue != expected {
                    let range = Range(match.range, in: text)!
                    text.replaceSubrange(range, with: expected)
                    repaired += 1
                }
            }
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        return repaired
    }

    private func isValidXMLIdentifier(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              first == "_" || CharacterSet.letters.contains(first) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return value.unicodeScalars.dropFirst().allSatisfy { allowed.contains($0) }
    }

    private func sanitizedIdentifier(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let body = String(value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" })
        return "mv-\(body.isEmpty ? "id" : body)"
    }

    private func containsMissingURL(in text: String, relativeTo file: URL, root: URL) -> Bool {
        !missingURLTokens(in: text, relativeTo: file, root: root).isEmpty
    }

    private func missingURLTokens(in text: String, relativeTo file: URL, root: URL) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"url\(\s*([\"']?)([^\"')]+)\1\s*\)"#,
            options: [.caseInsensitive]
        ) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            let token = nsText.substring(with: match.range)
            let value = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            return isMissingLocalResource(value, relativeTo: file, root: root) ? token : nil
        }
    }

    private func isMissingLocalResource(_ rawValue: String, relativeTo file: URL, root: URL) -> Bool {
        let lower = rawValue.lowercased()
        if lower.hasPrefix("data:") || lower.hasPrefix("http:") || lower.hasPrefix("https:") || rawValue.hasPrefix("#") {
            return false
        }
        let path = rawValue.split(separator: "#", maxSplits: 1).first.map(String.init) ?? rawValue
        let decoded = path.removingPercentEncoding ?? path
        let candidate = file.deletingLastPathComponent().appendingPathComponent(decoded).standardizedFileURL
        let rootPath = root.standardizedFileURL.path + "/"
        guard candidate.path.hasPrefix(rootPath) else { return true }
        return !FileManager.default.fileExists(atPath: candidate.path)
    }

    private func attribute(named name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*([\\\"'])([^\\\"']+)\\1",
            options: [.caseInsensitive]
        ) else { return nil }
        let nsTag = tag as NSString
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: nsTag.length)) else { return nil }
        return nsTag.substring(with: match.range(at: 2))
    }
}
