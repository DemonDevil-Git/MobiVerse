import Foundation
import Testing
@testable import Mobi2EpubTransferCore

struct PreviewReadingPositionStoreTests {
    @Test
    func savesReadingPositionForEachBook() throws {
        let directory = try TemporaryDirectory()
        let store = PreviewReadingPositionStore(
            storageURL: directory.url.appendingPathComponent("preview-positions.json")
        )
        let firstBook = directory.url.appendingPathComponent("First.epub")
        let secondBook = directory.url.appendingPathComponent("Second.epub")

        store.save(pageIndex: 42, for: firstBook)

        #expect(store.pageIndex(for: firstBook) == 42)
        #expect(store.pageIndex(for: secondBook) == nil)
    }

    @Test
    func replacesPreviousPositionAndClampsNegativeValues() throws {
        let directory = try TemporaryDirectory()
        let store = PreviewReadingPositionStore(
            storageURL: directory.url.appendingPathComponent("preview-positions.json")
        )
        let book = directory.url.appendingPathComponent("Comic.epub")

        store.save(pageIndex: 18, for: book)
        store.save(pageIndex: -3, for: book)

        #expect(store.pageIndex(for: book) == 0)
    }
}
