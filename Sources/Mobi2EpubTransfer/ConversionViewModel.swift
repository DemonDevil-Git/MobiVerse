import AppKit
import Foundation
import Mobi2EpubTransferCore
import SwiftUI

@MainActor
final class ConversionViewModel: ObservableObject {
    @Published private(set) var tasks: [ConversionTask] = []
    @Published private(set) var toolchain: ToolchainAvailability
    @Published var isImporterPresented = false

    private let locator: CommandLocator
    private let outputPolicy: FileOutputPolicy
    private let historyStore: ConversionHistoryStore
    private var isProcessing = false

    init(
        locator: CommandLocator = CommandLocator(),
        outputPolicy: FileOutputPolicy = FileOutputPolicy(),
        historyStore: ConversionHistoryStore = ConversionHistoryStore()
    ) {
        self.locator = locator
        self.outputPolicy = outputPolicy
        self.historyStore = historyStore
        self.toolchain = locator.inspectToolchain()
        self.tasks = historyStore.load()
    }

    var acceptedExtensions: Set<String> {
        ["mobi", "azw", "azw3"]
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

    func addFiles(_ urls: [URL]) {
        let filteredURLs = urls.filter { acceptedExtensions.contains($0.pathExtension.lowercased()) }
        let existingInputs = Set(tasks.map(\.inputURL))
        let newTasks = filteredURLs
            .filter { !existingInputs.contains($0) }
            .map { ConversionTask(inputURL: $0) }

        guard !newTasks.isEmpty else { return }
        tasks.append(contentsOf: newTasks)
        persistTasks()
        startProcessingIfNeeded()
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

    func openReport(for task: ConversionTask) {
        guard let reportURL = task.reportURL else { return }
        NSWorkspace.shared.open(reportURL)
    }

    func deleteTask(_ task: ConversionTask) {
        guard canDelete(task) else { return }
        tasks.removeAll { $0.id == task.id }
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
        tasks[index].status = .checkingTools
        tasks[index].progress = 0.1
        tasks[index].statusMessage = "Checking Calibre and EPUBCheck"
        persistTasks()
        refreshToolchain()

        guard toolchain.hasCalibre else {
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
            tasks[index].progress = 0.45
            tasks[index].statusMessage = "Converting with Calibre"
            persistTasks()

            let conversion = try await converter.convert(inputURL: tasks[index].inputURL, outputURL: outputURL)
            tasks[index].log = conversion.log

            tasks[index].statusMessage = "Optimizing comic EPUB layout"
            tasks[index].progress = 0.65
            persistTasks()
            let postProcessor = ComicEpubPostProcessor()
            let postProcessResult = try await postProcessor.process(epubURL: outputURL)

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
                postProcessReport: postProcessResult.reportText
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

    private func message(for error: FileOutputPolicyError) -> String {
        switch error {
        case .unsupportedInputExtension:
            "Only MOBI, AZW, and AZW3 files are supported."
        case .missingParentDirectory:
            "The source file folder could not be resolved."
        }
    }
}
