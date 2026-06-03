import Foundation

public struct ToolchainAvailability: Equatable, Sendable {
    public let ebookConvertURL: URL?
    public let ebookMetaURL: URL?
    public let epubCheckURL: URL?
    public let calibreSource: CalibreSource

    public var hasCalibre: Bool {
        ebookConvertURL != nil && ebookMetaURL != nil
    }

    public var missingCalibreMessage: String? {
        guard !hasCalibre else { return nil }
        return "Bundled Calibre was not found. Build the app with scripts/package-app.sh, or install Calibre and make sure ebook-convert and ebook-meta are available."
    }
}

public enum CalibreSource: Equatable, Sendable {
    case bundled
    case system
    case missing

    public var displayName: String {
        switch self {
        case .bundled: "Bundled Calibre"
        case .system: "System Calibre"
        case .missing: "Calibre missing"
        }
    }
}

public struct CommandLocator {
    private let fileManager: FileManager
    private let pathValue: String
    private let additionalSearchPaths: [String]
    private let bundledSearchPaths: [String]

    public init(
        fileManager: FileManager = .default,
        pathValue: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        resourceURL: URL? = Bundle.main.resourceURL,
        additionalSearchPaths: [String] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/Applications/calibre.app/Contents/MacOS"
        ]
    ) {
        self.fileManager = fileManager
        self.pathValue = pathValue
        self.additionalSearchPaths = additionalSearchPaths
        self.bundledSearchPaths = Self.bundledCalibreSearchPaths(resourceURL: resourceURL)
    }

    public func inspectToolchain() -> ToolchainAvailability {
        let bundledConvertURL = findBundledExecutable(named: "ebook-convert")
        let bundledMetaURL = findBundledExecutable(named: "ebook-meta")
        if bundledConvertURL != nil && bundledMetaURL != nil {
            return ToolchainAvailability(
                ebookConvertURL: bundledConvertURL,
                ebookMetaURL: bundledMetaURL,
                epubCheckURL: findBundledExecutable(named: "epubcheck") ?? findExecutable(named: "epubcheck"),
                calibreSource: .bundled
            )
        }

        let systemConvertURL = findExecutable(named: "ebook-convert")
        let systemMetaURL = findExecutable(named: "ebook-meta")
        return ToolchainAvailability(
            ebookConvertURL: systemConvertURL,
            ebookMetaURL: systemMetaURL,
            epubCheckURL: findExecutable(named: "epubcheck"),
            calibreSource: systemConvertURL != nil && systemMetaURL != nil ? .system : .missing
        )
    }

    public func findBundledExecutable(named name: String) -> URL? {
        findExecutable(named: name, in: bundledSearchPaths)
    }

    public func findExecutable(named name: String) -> URL? {
        findExecutable(named: name, in: pathValue.split(separator: ":").map(String.init) + additionalSearchPaths)
    }

    private func findExecutable(named name: String, in searchPaths: [String]) -> URL? {
        var seen = Set<String>()
        for directory in searchPaths where !directory.isEmpty {
            guard seen.insert(directory).inserted else { continue }
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func bundledCalibreSearchPaths(resourceURL: URL?) -> [String] {
        guard let resourceURL else { return [] }
        return [
            resourceURL
                .appendingPathComponent("ThirdParty")
                .appendingPathComponent("calibre.app")
                .appendingPathComponent("Contents")
                .appendingPathComponent("MacOS")
                .path,
            resourceURL
                .appendingPathComponent("calibre.app")
                .appendingPathComponent("Contents")
                .appendingPathComponent("MacOS")
                .path,
            resourceURL
                .appendingPathComponent("ThirdParty")
                .appendingPathComponent("epubcheck")
                .path
        ]
    }
}
