import Foundation

public enum DownloadedBookValidationError: Error, Equatable, LocalizedError {
    case unsupportedOrDisguisedFile

    public var errorDescription: String? {
        "The download is not a supported EPUB, MOBI, AZW, comic archive, or PDF file."
    }
}

public enum DownloadedBookValidator {
    public static func validatedExtension(at url: URL, suggestedExtension: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 4096) ?? Data()
        let ext = suggestedExtension.lowercased()
        let zip = header.starts(with: [0x50, 0x4B])
        let pdf = String(data: header.prefix(5), encoding: .ascii) == "%PDF-"
        let rar = String(data: header.prefix(4), encoding: .ascii) == "Rar!"
        let mobi = header.count >= 68 && String(data: header[60..<68], encoding: .ascii)?.contains("BOOKMOBI") == true
        let epub = zip && header.range(of: Data("application/epub+zip".utf8)) != nil
        let prefix = String(data: header.prefix(256), encoding: .utf8)?.lowercased() ?? ""
        let looksLikeHTML = prefix.contains("<!doctype html") || prefix.contains("<html")
        let executableMagic: [[UInt8]] = [[0xCF, 0xFA, 0xED, 0xFE], [0xCE, 0xFA, 0xED, 0xFE], [0x4D, 0x5A]]
        guard !looksLikeHTML, !executableMagic.contains(where: { header.starts(with: $0) }) else {
            throw DownloadedBookValidationError.unsupportedOrDisguisedFile
        }
        switch ext {
        case "epub" where epub: return "epub"
        case "cbz" where zip: return "cbz"
        case "zip" where zip: return "zip"
        case "pdf" where pdf: return "pdf"
        case "cbr" where rar: return "cbr"
        case "mobi" where mobi: return "mobi"
        case "azw" where mobi: return "azw"
        case "azw3" where mobi: return "azw3"
        default:
            if epub { return "epub" }
            if pdf { return "pdf" }
            if rar { return "cbr" }
            if mobi { return ext.isEmpty ? "mobi" : ext }
            if zip { return "zip" }
            throw DownloadedBookValidationError.unsupportedOrDisguisedFile
        }
    }
}
