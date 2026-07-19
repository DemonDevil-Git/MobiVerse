import Foundation
import Testing
@testable import Mobi2EpubTransferCore

struct DownloadedBookValidatorTests {
    @Test
    func acceptsSupportedFileSignatures() throws {
        let directory = try TemporaryDirectory()
        let pdf = directory.url.appendingPathComponent("download")
        try Data("%PDF-1.7".utf8).write(to: pdf)
        #expect(try DownloadedBookValidator.validatedExtension(at: pdf, suggestedExtension: "pdf") == "pdf")

        let epub = directory.url.appendingPathComponent("book.download")
        try (Data([0x50, 0x4B, 0x03, 0x04]) + Data("application/epub+zip".utf8)).write(to: epub)
        #expect(try DownloadedBookValidator.validatedExtension(at: epub, suggestedExtension: "epub") == "epub")
    }

    @Test
    func rejectsHTMLAndExecutablesWithBookExtensions() throws {
        let directory = try TemporaryDirectory()
        let html = directory.url.appendingPathComponent("fake.epub")
        try Data("<!doctype html><html>Error</html>".utf8).write(to: html)
        #expect(throws: DownloadedBookValidationError.unsupportedOrDisguisedFile) {
            try DownloadedBookValidator.validatedExtension(at: html, suggestedExtension: "epub")
        }

        let executable = directory.url.appendingPathComponent("fake.pdf")
        try Data([0x4D, 0x5A, 0, 0]).write(to: executable)
        #expect(throws: DownloadedBookValidationError.unsupportedOrDisguisedFile) {
            try DownloadedBookValidator.validatedExtension(at: executable, suggestedExtension: "pdf")
        }
    }
}
