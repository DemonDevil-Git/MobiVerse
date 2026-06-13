import Foundation

public struct SupportedInputFormat: Equatable, Sendable {
    public let fileExtension: String
    public let displayName: String
    public let isZipComicArchive: Bool

    public init(fileExtension: String, displayName: String, isZipComicArchive: Bool = false) {
        self.fileExtension = fileExtension
        self.displayName = displayName
        self.isZipComicArchive = isZipComicArchive
    }

    public static let all: [SupportedInputFormat] = [
        SupportedInputFormat(fileExtension: "mobi", displayName: "MOBI"),
        SupportedInputFormat(fileExtension: "azw", displayName: "AZW"),
        SupportedInputFormat(fileExtension: "azw3", displayName: "AZW3"),
        SupportedInputFormat(fileExtension: "cbz", displayName: "CBZ"),
        SupportedInputFormat(fileExtension: "cbr", displayName: "CBR"),
        SupportedInputFormat(fileExtension: "zip", displayName: "ZIP", isZipComicArchive: true),
        SupportedInputFormat(fileExtension: "pdf", displayName: "PDF")
    ]

    public static let supportedExtensions = Set(all.map(\.fileExtension))

    public static var displayList: String {
        all.map(\.displayName).joined(separator: ", ")
    }

    public static func format(for url: URL) -> SupportedInputFormat? {
        let fileExtension = url.pathExtension.lowercased()
        return all.first { $0.fileExtension == fileExtension }
    }
}
