import Foundation
import Testing
@testable import Mobi2EpubTransferCore

struct ConversionHistoryStoreTests {
    @Test
    func savesAndLoadsConversionHistory() throws {
        let directory = try TemporaryDirectory()
        let historyURL = directory.url.appendingPathComponent("history.json")
        let inputURL = directory.url.appendingPathComponent("Book.mobi")
        let outputURL = directory.url.appendingPathComponent("Book.epub")
        let reportURL = directory.url.appendingPathComponent("Book.conversion-report.txt")
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let task = ConversionTask(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            inputURL: inputURL,
            outputURL: outputURL,
            status: .succeeded,
            progress: 1,
            statusMessage: "EPUB created and validated",
            log: "conversion log",
            reportURL: reportURL,
            completedAt: completedAt
        )
        let store = ConversionHistoryStore(historyURL: historyURL)

        store.save([task])
        let loadedTasks = store.load()

        #expect(loadedTasks == [task])
    }

    @Test
    func restoresInterruptedConversionAsFailed() throws {
        let directory = try TemporaryDirectory()
        let historyURL = directory.url.appendingPathComponent("history.json")
        let task = ConversionTask(
            inputURL: directory.url.appendingPathComponent("Comic.azw3"),
            status: .converting,
            progress: 0.45,
            statusMessage: "Converting with Calibre"
        )
        let store = ConversionHistoryStore(historyURL: historyURL)

        store.save([task])
        let restoredTask = try #require(store.load().first)

        #expect(restoredTask.status == .failed)
        #expect(restoredTask.progress == 1)
        #expect(restoredTask.statusMessage == "Interrupted before completion")
        #expect(restoredTask.completedAt != nil)
    }

    @Test
    func legacyHistoryDefaultsToClassicComicProfile() throws {
        let directory = try TemporaryDirectory()
        let historyURL = directory.url.appendingPathComponent("history.json")
        let task = ConversionTask(inputURL: directory.url.appendingPathComponent("Legacy.mobi"))
        let encoder = JSONEncoder()
        var object = try #require(try JSONSerialization.jsonObject(with: encoder.encode([task])) as? [[String: Any]])
        object[0].removeValue(forKey: "conversionProfile")
        object[0].removeValue(forKey: "readingDirection")
        object[0].removeValue(forKey: "importSource")
        object[0].removeValue(forKey: "detectedKind")
        try JSONSerialization.data(withJSONObject: object).write(to: historyURL)

        let restored = try #require(ConversionHistoryStore(historyURL: historyURL).load().first)
        #expect(restored.conversionProfile == .comicFixedLayout)
        #expect(restored.readingDirection == .rightToLeft)
    }
}
