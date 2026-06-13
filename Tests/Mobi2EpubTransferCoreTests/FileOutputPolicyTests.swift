import Foundation
import Testing
@testable import Mobi2EpubTransferCore

struct FileOutputPolicyTests {
    @Test
    func outputURLUsesSameDirectoryAndEpubExtension() throws {
        let directory = try TemporaryDirectory()
        let inputURL = directory.url.appendingPathComponent("Book.mobi")
        FileManager.default.createFile(atPath: inputURL.path, contents: Data())

        let outputURL = try FileOutputPolicy().epubOutputURL(for: inputURL)

        #expect(outputURL == directory.url.appendingPathComponent("Book.epub"))
    }

    @Test
    func outputURLDoesNotOverwriteExistingFiles() throws {
        let directory = try TemporaryDirectory()
        let inputURL = directory.url.appendingPathComponent("Comic.azw3")
        let firstOutput = directory.url.appendingPathComponent("Comic.epub")
        let secondOutput = directory.url.appendingPathComponent("Comic 2.epub")
        FileManager.default.createFile(atPath: inputURL.path, contents: Data())
        FileManager.default.createFile(atPath: firstOutput.path, contents: Data())
        FileManager.default.createFile(atPath: secondOutput.path, contents: Data())

        let outputURL = try FileOutputPolicy().epubOutputURL(for: inputURL)

        #expect(outputURL == directory.url.appendingPathComponent("Comic 3.epub"))
    }

    @Test
    func outputURLSupportsComicArchiveAndPDFInputs() throws {
        let directory = try TemporaryDirectory()
        for fileExtension in ["cbz", "cbr", "zip", "pdf"] {
            let inputURL = directory.url.appendingPathComponent("Comic.\(fileExtension)")
            FileManager.default.createFile(atPath: inputURL.path, contents: Data())

            let outputURL = try FileOutputPolicy().epubOutputURL(for: inputURL)

            #expect(outputURL.pathExtension == "epub")
            #expect(outputURL.deletingPathExtension().lastPathComponent.hasPrefix("Comic"))
        }
    }

    @Test
    func unsupportedInputExtensionThrows() throws {
        let directory = try TemporaryDirectory()
        let inputURL = directory.url.appendingPathComponent("Notes.txt")

        #expect(throws: FileOutputPolicyError.unsupportedInputExtension("txt")) {
            _ = try FileOutputPolicy().epubOutputURL(for: inputURL)
        }
    }
}
