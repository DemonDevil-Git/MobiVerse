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

    @Test
    func savesAndRestoresTextSectionAndPage() throws {
        let directory = try TemporaryDirectory()
        let store = PreviewReadingPositionStore(
            storageURL: directory.url.appendingPathComponent("preview-positions.json")
        )
        let book = directory.url.appendingPathComponent("Novel.epub")

        store.save(position: PreviewReadingPosition(sectionIndex: 12, pageIndex: 7), for: book)

        #expect(
            store.position(for: book, legacyInterpretation: .section)
                == PreviewReadingPosition(sectionIndex: 12, pageIndex: 7)
        )
    }

    @Test
    func interpretsLegacyValuesForComicOrTextWithoutRewritingOtherBooks() throws {
        let directory = try TemporaryDirectory()
        let storageURL = directory.url.appendingPathComponent("preview-positions.json")
        let comic = directory.url.appendingPathComponent("Comic.epub")
        let novel = directory.url.appendingPathComponent("Novel.epub")
        let legacy = [comic.standardizedFileURL.path: 18, novel.standardizedFileURL.path: 9]
        try JSONEncoder().encode(legacy).write(to: storageURL)
        let store = PreviewReadingPositionStore(storageURL: storageURL)

        #expect(
            store.position(for: comic, legacyInterpretation: .page)
                == PreviewReadingPosition(sectionIndex: 0, pageIndex: 18)
        )
        #expect(
            store.position(for: novel, legacyInterpretation: .section)
                == PreviewReadingPosition(sectionIndex: 9, pageIndex: 0)
        )

        store.save(position: PreviewReadingPosition(sectionIndex: 9, pageIndex: 4), for: novel)

        #expect(store.pageIndex(for: comic) == 18)
        #expect(
            store.position(for: novel, legacyInterpretation: .section)
                == PreviewReadingPosition(sectionIndex: 9, pageIndex: 4)
        )
    }
}
