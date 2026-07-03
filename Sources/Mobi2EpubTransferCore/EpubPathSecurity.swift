import Foundation

public enum EpubPathSecurity {
    public static func resolve(
        _ reference: String,
        relativeTo baseDirectory: URL,
        containedIn rootDirectory: URL
    ) -> URL? {
        guard !reference.isEmpty, !reference.contains("\0") else { return nil }

        let pathOnly = reference
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        guard
            !pathOnly.isEmpty,
            let decodedPath = String(pathOnly).removingPercentEncoding,
            !decodedPath.isEmpty,
            !decodedPath.hasPrefix("/"),
            !decodedPath.hasPrefix("\\"),
            URL(string: decodedPath)?.scheme == nil
        else {
            return nil
        }

        let candidate = baseDirectory
            .appendingPathComponent(decodedPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        return contains(candidate, in: rootDirectory) ? candidate : nil
    }

    public static func contains(_ candidate: URL, in rootDirectory: URL) -> Bool {
        guard candidate.isFileURL, rootDirectory.isFileURL else { return false }
        let root = rootDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        let path = candidate.standardizedFileURL.resolvingSymlinksInPath().path
        return path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
