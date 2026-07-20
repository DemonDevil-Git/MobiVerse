import Foundation

public struct BrowserNavigationResponseInfo: Equatable, Sendable {
    public let url: URL?
    public let mimeType: String?
    public let suggestedFilename: String?
    public let contentDisposition: String?
    public let isForMainFrame: Bool
    public let canShowMIMEType: Bool

    public init(
        url: URL?,
        mimeType: String?,
        suggestedFilename: String?,
        contentDisposition: String?,
        isForMainFrame: Bool,
        canShowMIMEType: Bool
    ) {
        self.url = url
        self.mimeType = mimeType
        self.suggestedFilename = suggestedFilename
        self.contentDisposition = contentDisposition
        self.isForMainFrame = isForMainFrame
        self.canShowMIMEType = canShowMIMEType
    }
}

public enum BrowserDownloadPolicy {
    private static let bookMIMETypes: Set<String> = [
        "application/epub+zip",
        "application/x-mobipocket-ebook",
        "application/vnd.amazon.ebook",
        "application/zip",
        "application/x-rar-compressed",
        "application/vnd.rar"
    ]
    private static let bookExtensions: Set<String> = [
        "epub", "mobi", "azw", "azw3", "cbz", "cbr", "zip"
    ]

    public static func shouldDownload(
        _ response: BrowserNavigationResponseInfo,
        automaticallyDownloadsPDFs: Bool
    ) -> Bool {
        if !response.canShowMIMEType {
            return true
        }
        guard response.isForMainFrame else {
            return false
        }

        let disposition = response.contentDisposition?.lowercased() ?? ""
        if disposition.contains("attachment") {
            return true
        }

        let mimeType = response.mimeType?
            .lowercased()
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init) ?? ""
        if bookMIMETypes.contains(mimeType) {
            return true
        }

        let extensions = candidateExtensions(for: response)
        if !bookExtensions.isDisjoint(with: extensions) {
            return true
        }

        return automaticallyDownloadsPDFs
            && (mimeType == "application/pdf" || extensions.contains("pdf"))
    }

    private static func candidateExtensions(for response: BrowserNavigationResponseInfo) -> Set<String> {
        var extensions: Set<String> = []
        if let urlExtension = response.url?.pathExtension.lowercased(), !urlExtension.isEmpty {
            extensions.insert(urlExtension)
        }
        if let filename = response.suggestedFilename {
            let filenameExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
            if !filenameExtension.isEmpty {
                extensions.insert(filenameExtension)
            }
        }
        return extensions
    }
}
