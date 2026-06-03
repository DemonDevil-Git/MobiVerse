import Foundation
import Testing
@testable import Mobi2EpubTransferCore

struct CommandLocatorTests {
    @Test
    func findsExecutableInProvidedPath() throws {
        let directory = try TemporaryDirectory()
        let executableURL = directory.url.appendingPathComponent("ebook-convert")
        FileManager.default.createFile(atPath: executableURL.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let locator = CommandLocator(
            pathValue: directory.url.path,
            additionalSearchPaths: []
        )

        #expect(locator.findExecutable(named: "ebook-convert") == executableURL)
    }

    @Test
    func reportsMissingCalibreWhenEitherCommandIsMissing() throws {
        let directory = try TemporaryDirectory()
        let executableURL = directory.url.appendingPathComponent("ebook-convert")
        FileManager.default.createFile(atPath: executableURL.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let locator = CommandLocator(
            pathValue: directory.url.path,
            additionalSearchPaths: []
        )

        #expect(locator.inspectToolchain().hasCalibre == false)
    }

    @Test
    func bundledCalibreTakesPrecedenceOverSystemCalibre() throws {
        let resourceDirectory = try TemporaryDirectory()
        let bundledDirectory = resourceDirectory.url
            .appendingPathComponent("ThirdParty")
            .appendingPathComponent("calibre.app")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: bundledDirectory, withIntermediateDirectories: true)
        try makeExecutable(named: "ebook-convert", in: bundledDirectory)
        try makeExecutable(named: "ebook-meta", in: bundledDirectory)

        let systemDirectory = try TemporaryDirectory()
        try makeExecutable(named: "ebook-convert", in: systemDirectory.url)
        try makeExecutable(named: "ebook-meta", in: systemDirectory.url)

        let locator = CommandLocator(
            pathValue: systemDirectory.url.path,
            resourceURL: resourceDirectory.url,
            additionalSearchPaths: []
        )

        let toolchain = locator.inspectToolchain()

        #expect(toolchain.calibreSource == .bundled)
        #expect(toolchain.ebookConvertURL == bundledDirectory.appendingPathComponent("ebook-convert"))
    }

    @Test
    func fallsBackToSystemCalibreWhenBundleIsMissing() throws {
        let resourceDirectory = try TemporaryDirectory()
        let systemDirectory = try TemporaryDirectory()
        try makeExecutable(named: "ebook-convert", in: systemDirectory.url)
        try makeExecutable(named: "ebook-meta", in: systemDirectory.url)

        let locator = CommandLocator(
            pathValue: systemDirectory.url.path,
            resourceURL: resourceDirectory.url,
            additionalSearchPaths: []
        )

        #expect(locator.inspectToolchain().calibreSource == .system)
    }

    @Test
    func findsBundledEPUBCheckWrapper() throws {
        let resourceDirectory = try TemporaryDirectory()
        let bundledCalibreDirectory = resourceDirectory.url
            .appendingPathComponent("ThirdParty")
            .appendingPathComponent("calibre.app")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
        let bundledEPUBCheckDirectory = resourceDirectory.url
            .appendingPathComponent("ThirdParty")
            .appendingPathComponent("epubcheck")
        try FileManager.default.createDirectory(at: bundledCalibreDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundledEPUBCheckDirectory, withIntermediateDirectories: true)
        try makeExecutable(named: "ebook-convert", in: bundledCalibreDirectory)
        try makeExecutable(named: "ebook-meta", in: bundledCalibreDirectory)
        try makeExecutable(named: "epubcheck", in: bundledEPUBCheckDirectory)

        let locator = CommandLocator(
            pathValue: "",
            resourceURL: resourceDirectory.url,
            additionalSearchPaths: []
        )

        #expect(locator.inspectToolchain().epubCheckURL == bundledEPUBCheckDirectory.appendingPathComponent("epubcheck"))
    }

    private func makeExecutable(named name: String, in directory: URL) throws {
        let executableURL = directory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: executableURL.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
    }
}
