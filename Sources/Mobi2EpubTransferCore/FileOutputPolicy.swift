import Foundation

public enum FileOutputPolicyError: Error, Equatable {
    case unsupportedInputExtension(String)
    case missingParentDirectory
}

public struct FileOutputPolicy {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func epubOutputURL(for inputURL: URL) throws -> URL {
        let supportedExtensions = ["mobi", "azw", "azw3"]
        let inputExtension = inputURL.pathExtension.lowercased()
        guard supportedExtensions.contains(inputExtension) else {
            throw FileOutputPolicyError.unsupportedInputExtension(inputExtension)
        }

        guard inputURL.deletingLastPathComponent().path != inputURL.path else {
            throw FileOutputPolicyError.missingParentDirectory
        }

        return availableURL(
            in: inputURL.deletingLastPathComponent(),
            baseName: inputURL.deletingPathExtension().lastPathComponent,
            pathExtension: "epub"
        )
    }

    public func reportURL(for outputURL: URL) -> URL {
        availableURL(
            in: outputURL.deletingLastPathComponent(),
            baseName: outputURL.deletingPathExtension().lastPathComponent,
            pathExtension: "conversion-report.txt"
        )
    }

    private func availableURL(in directory: URL, baseName: String, pathExtension: String) -> URL {
        let firstCandidate = directory.appendingPathComponent(baseName).appendingPathExtension(pathExtension)
        guard fileManager.fileExists(atPath: firstCandidate.path) else {
            return firstCandidate
        }

        var index = 2
        while true {
            let candidate = directory
                .appendingPathComponent("\(baseName) \(index)")
                .appendingPathExtension(pathExtension)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}
