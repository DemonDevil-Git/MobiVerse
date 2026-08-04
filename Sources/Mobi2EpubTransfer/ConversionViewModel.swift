import AppKit
import Foundation
import Mobi2EpubTransferCore
import SwiftUI

@MainActor
final class ConversionViewModel: ObservableObject {
    @Published private(set) var tasks: [ConversionTask] = []
    @Published private(set) var toolchain: ToolchainAvailability
    @Published private(set) var coverImages: [UUID: NSImage] = [:]
    @Published private(set) var showcaseCoverImages: [UUID: NSImage] = [:]
    @Published private(set) var bookMetadata: [UUID: EpubBookMetadata] = [:]
    @Published var isImporterPresented = false

    private let locator: CommandLocator
    private let outputPolicy: FileOutputPolicy
    private let historyStore: ConversionHistoryStore
    private let coverThumbnailCache: CoverThumbnailCache
    private let bookMetadataCache: BookMetadataCache
    private var isProcessing = false
    private var loadingCoverTaskIDs: Set<UUID> = []
    private var loadingShowcaseCoverTaskIDs: Set<UUID> = []
    private var loadingMetadataTaskIDs: Set<UUID> = []
    private var coverWarmupTask: Task<Void, Never>?
    private var shelfAssetLoadingTask: Task<Void, Never>?

    init(
        locator: CommandLocator = CommandLocator(),
        outputPolicy: FileOutputPolicy = FileOutputPolicy(),
        historyStore: ConversionHistoryStore = ConversionHistoryStore(),
        coverThumbnailCache: CoverThumbnailCache = CoverThumbnailCache(),
        bookMetadataCache: BookMetadataCache = BookMetadataCache()
    ) {
        self.locator = locator
        self.outputPolicy = outputPolicy
        self.historyStore = historyStore
        self.coverThumbnailCache = coverThumbnailCache
        self.bookMetadataCache = bookMetadataCache
        self.toolchain = locator.inspectToolchain()
        self.tasks = historyStore.load()
        loadCachedCoverImagesForCompletedTasks()
        loadCachedBookMetadataForCompletedTasks()
        requestCoverImagesForCompletedTasks()
    }

    var acceptedExtensions: Set<String> {
        SupportedInputFormat.supportedExtensions
    }

    var canConvert: Bool {
        toolchain.hasCalibre
    }

    var missingToolsMessage: String? {
        toolchain.missingCalibreMessage
    }

    func refreshToolchain() {
        toolchain = locator.inspectToolchain()
    }

    @discardableResult
    func addFiles(_ urls: [URL]) -> [ConversionTask] {
        addReviewedFiles(urls.map {
            ReviewedImport(
                url: $0,
                source: .filePicker,
                detectedKind: .comic,
                profile: .comicFixedLayout,
                readingDirection: .rightToLeft
            )
        })
    }

    @discardableResult
    func addReviewedFiles(_ imports: [ReviewedImport]) -> [ConversionTask] {
        var addedOrExistingTasks: [ConversionTask] = []
        var newTasks: [ConversionTask] = []
        var didQueueTask = false

        for item in imports where acceptedExtensions.contains(item.url.pathExtension.lowercased()) {
            let url = item.url
            if let existingIndex = tasks.firstIndex(where: { $0.inputURL == url }) {
                if [.queued, .checkingTools, .converting, .validating].contains(tasks[existingIndex].status) {
                    addedOrExistingTasks.append(tasks[existingIndex])
                    continue
                }
                let needsReconversion = tasks[existingIndex].conversionProfile != item.profile
                    || tasks[existingIndex].readingDirection != item.readingDirection
                tasks[existingIndex].importSource = item.source
                tasks[existingIndex].detectedKind = item.detectedKind
                tasks[existingIndex].conversionProfile = item.profile
                tasks[existingIndex].readingDirection = item.readingDirection
                if tasks[existingIndex].status == .failed
                    || isOutputMissing(for: tasks[existingIndex])
                    || needsReconversion {
                    discardPresentationAssets(for: tasks[existingIndex])
                    tasks[existingIndex].status = .queued
                    tasks[existingIndex].progress = 0
                    tasks[existingIndex].statusMessage = "Waiting"
                    tasks[existingIndex].outputURL = nil
                    tasks[existingIndex].reportURL = nil
                    tasks[existingIndex].log = ""
                    tasks[existingIndex].completedAt = nil
                    didQueueTask = true
                }
                addedOrExistingTasks.append(tasks[existingIndex])
            } else {
                let task = ConversionTask(
                    inputURL: url,
                    importSource: item.source,
                    detectedKind: item.detectedKind,
                    conversionProfile: item.profile,
                    readingDirection: item.readingDirection
                )
                newTasks.append(task)
                addedOrExistingTasks.append(task)
                didQueueTask = true
            }
        }

        if !newTasks.isEmpty {
            tasks.append(contentsOf: newTasks)
        }
        if !imports.isEmpty {
            persistTasks()
        }
        if didQueueTask {
            startProcessingIfNeeded()
        }

        return addedOrExistingTasks
    }

    func task(withID id: UUID) -> ConversionTask? {
        tasks.first { $0.id == id }
    }

    @discardableResult
    func addEpubToLibrary(_ url: URL) -> ConversionTask {
        if let existingTask = tasks.first(where: {
            sameFile($0.inputURL, url) || $0.outputURL.map { sameFile($0, url) } == true
        }) {
            return existingTask
        }

        let task = ConversionTask(
            inputURL: url,
            outputURL: url,
            status: .succeeded,
            progress: 1,
            statusMessage: "EPUB ready to read",
            completedAt: Date()
        )
        tasks.append(task)
        persistTasks()
        requestCoverImage(for: task)
        return task
    }

    func requeueTask(_ task: ConversionTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        switch tasks[index].status {
        case .checkingTools, .converting, .validating, .queued:
            return
        case .succeeded, .succeededWithWarnings, .failed:
            discardPresentationAssets(for: tasks[index])
            tasks[index].status = .queued
            tasks[index].progress = 0
            tasks[index].statusMessage = "Waiting"
            tasks[index].outputURL = nil
            tasks[index].reportURL = nil
            tasks[index].log = ""
            tasks[index].completedAt = nil
            persistTasks()
            startProcessingIfNeeded()
        }
    }

    func retryFailedTasks() {
        for index in tasks.indices where tasks[index].status == .failed {
            tasks[index].status = .queued
            tasks[index].progress = 0
            tasks[index].statusMessage = "Waiting"
            tasks[index].completedAt = nil
        }
        persistTasks()
        startProcessingIfNeeded()
    }

    func revealOutput(for task: ConversionTask) {
        guard let outputURL = task.outputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
    }

    func coverImage(for task: ConversionTask) -> NSImage? {
        coverImages[task.id]
    }

    func showcaseCoverImage(for task: ConversionTask) -> NSImage? {
        showcaseCoverImages[task.id]
    }

    func metadata(for task: ConversionTask) -> EpubBookMetadata? {
        bookMetadata[task.id]
    }

    func requestCoverImage(for task: ConversionTask) {
        Task {
            await loadCoverImageIfNeeded(for: task)
        }
    }

    func requestShelfAssets(for task: ConversionTask) {
        coverWarmupTask?.cancel()
        shelfAssetLoadingTask?.cancel()
        shelfAssetLoadingTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await loadCoverImageIfNeeded(for: task)
            guard !Task.isCancelled else { return }
            await loadShowcaseCoverImageIfNeeded(for: task)
            guard !Task.isCancelled else { return }
            await loadBookMetadataIfNeeded(for: task)
        }
    }

    func openReport(for task: ConversionTask) {
        guard let reportURL = task.reportURL else { return }
        NSWorkspace.shared.open(reportURL)
    }

    func deleteTaskAndOutputFile(_ task: ConversionTask) throws {
        guard canDelete(task), let storedTask = tasks.first(where: { $0.id == task.id }) else { return }

        if let outputURL = storedTask.outputURL, FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        discardPresentationAssets(for: storedTask)
        tasks.removeAll { $0.id == storedTask.id }
        persistTasks()
    }

    func canDelete(_ task: ConversionTask) -> Bool {
        switch task.status {
        case .checkingTools, .converting, .validating:
            false
        case .queued, .succeeded, .succeededWithWarnings, .failed:
            true
        }
    }

    func isOutputMissing(for task: ConversionTask) -> Bool {
        guard
            task.status == .succeeded || task.status == .succeededWithWarnings,
            let outputURL = task.outputURL
        else {
            return false
        }
        return !FileManager.default.fileExists(atPath: outputURL.path)
    }

    private func sameFile(_ firstURL: URL, _ secondURL: URL) -> Bool {
        firstURL.standardizedFileURL.resolvingSymlinksInPath()
            == secondURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func startProcessingIfNeeded() {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            await processQueue()
            isProcessing = false
        }
    }

    private func processQueue() async {
        while let nextIndex = tasks.firstIndex(where: { $0.status == .queued }) {
            await processTask(at: nextIndex)
        }
    }

    private func processTask(at index: Int) async {
        let taskID = tasks[index].id
        let usesNativePDFConversion = tasks[index].inputURL.pathExtension.lowercased() == "pdf"
            && tasks[index].conversionProfile == .comicFixedLayout
        tasks[index].status = .checkingTools
        tasks[index].progress = 0.1
        tasks[index].statusMessage = usesNativePDFConversion
            ? "Preparing native PDF conversion"
            : "Checking Calibre and EPUBCheck"
        persistTasks()
        refreshToolchain()

        guard usesNativePDFConversion || toolchain.hasCalibre else {
            tasks[index].status = .failed
            tasks[index].progress = 1
            tasks[index].statusMessage = toolchain.missingCalibreMessage ?? "Calibre CLI is missing"
            tasks[index].completedAt = Date()
            persistTasks()
            return
        }

        do {
            let outputURL = try outputPolicy.epubOutputURL(for: tasks[index].inputURL)
            tasks[index].outputURL = outputURL

            let converter = ConverterService(ebookConvertURL: toolchain.ebookConvertURL)
            tasks[index].status = .converting
            tasks[index].progress = 0.12
            tasks[index].statusMessage = usesNativePDFConversion
                ? "Reading PDF pages"
                : "Converting with Calibre"
            persistTasks()

            let conversion = try await converter.convert(
                inputURL: tasks[index].inputURL,
                outputURL: outputURL,
                profile: tasks[index].conversionProfile,
                readingDirection: tasks[index].readingDirection
            ) { [weak self] update in
                Task { @MainActor in
                    self?.applyConversionProgress(update, toTaskID: taskID)
                }
            }
            tasks[index].log = conversion.log

            let postProcessReport: String
            if let completedReport = conversion.postProcessReport {
                tasks[index].statusMessage = "Preparing validation report"
                tasks[index].progress = 0.8
                postProcessReport = completedReport
            } else if tasks[index].conversionProfile == .comicFixedLayout {
                tasks[index].statusMessage = "Optimizing comic EPUB layout"
                tasks[index].progress = 0.65
                persistTasks()
                let postProcessor = ComicEpubPostProcessor()
                postProcessReport = try await postProcessor.process(
                    epubURL: outputURL,
                    readingDirection: tasks[index].readingDirection
                ).reportText
            } else {
                tasks[index].statusMessage = "Repairing text EPUB structure"
                tasks[index].progress = 0.72
                persistTasks()
                postProcessReport = try await TextEpubPostProcessor()
                    .process(epubURL: outputURL)
                    .reportText
            }

            let reportURL = outputPolicy.reportURL(for: outputURL)
            let validator = EpubValidator(epubCheckURL: toolchain.epubCheckURL)
            tasks[index].status = .validating
            tasks[index].progress = 0.8
            tasks[index].statusMessage = "Running EPUBCheck"
            persistTasks()

            let validation = try await validator.validate(
                epubURL: outputURL,
                reportURL: reportURL,
                conversionLog: conversion.log,
                postProcessReport: postProcessReport
            )
            tasks[index].reportURL = validation.reportURL
            tasks[index].progress = 1
            tasks[index].completedAt = Date()

            switch validation.status {
            case .passed:
                tasks[index].status = .succeeded
                tasks[index].statusMessage = "EPUB created and validated"
            case .skipped:
                tasks[index].status = .succeeded
                tasks[index].statusMessage = "EPUB created. Open the report for validation details."
            case .warnings:
                tasks[index].status = .succeededWithWarnings
                tasks[index].statusMessage = "EPUB created with validation warnings"
            case .failed:
                tasks[index].status = .failed
                tasks[index].statusMessage = "EPUBCheck failed. Review the report."
            }
            persistTasks()
            requestShelfAssets(for: tasks[index])
        } catch let error as ConversionServiceError {
            tasks[index].status = .failed
            tasks[index].progress = 1
            tasks[index].statusMessage = error.message
            tasks[index].log = error.log
            tasks[index].completedAt = Date()
            persistTasks()
        } catch let error as FileOutputPolicyError {
            tasks[index].status = .failed
            tasks[index].progress = 1
            tasks[index].statusMessage = message(for: error)
            tasks[index].completedAt = Date()
            persistTasks()
        } catch {
            tasks[index].status = .failed
            tasks[index].progress = 1
            tasks[index].statusMessage = error.localizedDescription
            tasks[index].completedAt = Date()
            persistTasks()
        }
    }

    private func persistTasks() {
        historyStore.save(tasks)
    }

    private func applyConversionProgress(_ update: ConversionProgressUpdate, toTaskID taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }), tasks[index].status == .converting else {
            return
        }
        tasks[index].progress = 0.12 + min(max(update.fraction, 0), 1) * 0.66
        tasks[index].statusMessage = update.message
    }

    private func requestCoverImagesForCompletedTasks() {
        coverWarmupTask?.cancel()
        coverWarmupTask = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, !Task.isCancelled else { return }

            for task in tasks {
                guard !Task.isCancelled else { return }
                await loadCoverImageIfNeeded(for: task)
                await Task.yield()
            }
        }
    }

    private func loadCachedCoverImagesForCompletedTasks() {
        for task in tasks {
            guard
                task.status == .succeeded || task.status == .succeededWithWarnings,
                let cachedImage = coverThumbnailCache.image(for: task)
            else {
                continue
            }
            coverImages[task.id] = cachedImage
        }
    }

    private func loadCachedBookMetadataForCompletedTasks() {
        for task in tasks {
            guard
                task.status == .succeeded || task.status == .succeededWithWarnings,
                let cachedMetadata = bookMetadataCache.metadata(for: task)
            else {
                continue
            }
            bookMetadata[task.id] = cachedMetadata
        }
    }

    private func loadCoverImageIfNeeded(for task: ConversionTask) async {
        guard
            (task.status == .succeeded || task.status == .succeededWithWarnings),
            coverImages[task.id] == nil,
            !loadingCoverTaskIDs.contains(task.id),
            let outputURL = task.outputURL,
            FileManager.default.fileExists(atPath: outputURL.path)
        else {
            return
        }

        loadingCoverTaskIDs.insert(task.id)
        defer { loadingCoverTaskIDs.remove(task.id) }

        let extractionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MobiVerseCoverCache", isDirectory: true)
            .appendingPathComponent(task.id.uuidString, isDirectory: true)

        do {
            guard
                let coverURL = try await EpubCoverImageExtractor().coverImageURL(
                    epubURL: outputURL,
                    extractionDirectory: extractionDirectory
                ),
                let image = NSImage(contentsOf: coverURL)
            else {
                return
            }
            let cachedImage = coverThumbnailCache.image(for: task)
            let displayImage = cachedImage ?? image
            if cachedImage == nil {
                coverThumbnailCache.save(image, for: task)
            }
            if coverThumbnailCache.showcaseImage(for: task) == nil {
                coverThumbnailCache.saveShowcase(image, for: task)
            }
            coverImages[task.id] = displayImage
        } catch {
            return
        }
    }

    private func loadShowcaseCoverImageIfNeeded(for task: ConversionTask) async {
        guard
            (task.status == .succeeded || task.status == .succeededWithWarnings),
            showcaseCoverImages[task.id] == nil,
            !loadingShowcaseCoverTaskIDs.contains(task.id),
            let outputURL = task.outputURL,
            FileManager.default.fileExists(atPath: outputURL.path)
        else {
            return
        }

        if let cachedImage = coverThumbnailCache.showcaseImage(for: task) {
            showcaseCoverImages[task.id] = cachedImage
            return
        }

        loadingShowcaseCoverTaskIDs.insert(task.id)
        defer { loadingShowcaseCoverTaskIDs.remove(task.id) }
        let extractionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MobiVerseShowcaseCoverCache", isDirectory: true)
            .appendingPathComponent(task.id.uuidString, isDirectory: true)

        do {
            guard
                let coverURL = try await EpubCoverImageExtractor().coverImageURL(
                    epubURL: outputURL,
                    extractionDirectory: extractionDirectory
                ),
                let image = NSImage(contentsOf: coverURL)
            else {
                return
            }
            coverThumbnailCache.saveShowcase(image, for: task)
            showcaseCoverImages[task.id] = coverThumbnailCache.showcaseImage(for: task) ?? image
        } catch {
            return
        }
    }

    private func loadBookMetadataIfNeeded(for task: ConversionTask) async {
        guard
            (task.status == .succeeded || task.status == .succeededWithWarnings),
            bookMetadata[task.id] == nil,
            !loadingMetadataTaskIDs.contains(task.id),
            let outputURL = task.outputURL,
            FileManager.default.fileExists(atPath: outputURL.path)
        else {
            return
        }

        if let cachedMetadata = bookMetadataCache.metadata(for: task) {
            bookMetadata[task.id] = cachedMetadata
            return
        }

        loadingMetadataTaskIDs.insert(task.id)
        defer { loadingMetadataTaskIDs.remove(task.id) }
        do {
            guard let metadata = try await EpubMetadataExtractor().metadata(epubURL: outputURL) else { return }
            bookMetadataCache.save(metadata, for: task)
            bookMetadata[task.id] = metadata
        } catch {
            return
        }
    }

    private func discardPresentationAssets(for task: ConversionTask) {
        coverImages[task.id] = nil
        showcaseCoverImages[task.id] = nil
        bookMetadata[task.id] = nil
        coverThumbnailCache.removeImage(for: task)
        bookMetadataCache.removeMetadata(for: task)
    }

    private func message(for error: FileOutputPolicyError) -> String {
        switch error {
        case .unsupportedInputExtension:
            "Only \(SupportedInputFormat.displayList) files are supported."
        case .missingParentDirectory:
            "The source file folder could not be resolved."
        }
    }
}
