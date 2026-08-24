import Mobi2EpubTransferCore
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppAppearancePreference.storageKey) private var appearanceRawValue = AppAppearancePreference.system.rawValue
    @AppStorage(AppLanguagePreference.storageKey) private var languageRawValue = AppLanguagePreference.simplifiedChinese.rawValue
    @StateObject private var viewModel = ConversionViewModel()
    @StateObject private var importReview = ImportReviewCoordinator()
    @StateObject private var browserTabs = BrowserTabStore()
    // Retain the manager without observing it at the app-content level. The
    // Browser workspace observes it directly when visible; otherwise large
    // download progress updates must not invalidate the 3D shelf hierarchy.
    @State private var browserDownloads = BrowserDownloadManager()
    @ObservedObject private var openBookRouter = OpenBookRouter.shared
    @State private var isSidebarVisible = true
    @State private var isToolStatusPresented = false
    @State private var previewWindowController: EpubPreviewWindowController?
    @State private var presentedAlert: ContentAlert?
    @State private var readingPreparation: ReadingPreparation?
    @State private var taskLayout = TaskLayout.grid
    @State private var workspace = AppWorkspace.library
    @State private var isImportReviewPresented = false
    @State private var shouldClearImportReviewOnDismiss = false

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                sidebar
                    .frame(width: 286)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Group {
                switch workspace {
                case .library:
                    mainContent
                case .browser:
                    BrowserWorkspace(tabs: browserTabs, downloads: browserDownloads) { url in
                        Task { await analyzeImports([url], source: .browserDownload) }
                    }
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.18), value: isSidebarVisible)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    isSidebarVisible.toggle()
                } label: {
                    Label("Toggle sidebar", systemImage: "sidebar.leading")
                }
                .help(L10n.string(isSidebarVisible ? "Hide sidebar" : "Show sidebar"))
            }

            ToolbarItem(placement: .primaryAction) {
                ToolStatusButton(
                    toolchain: viewModel.toolchain,
                    canConvert: viewModel.canConvert,
                    missingToolsMessage: viewModel.missingToolsMessage,
                    detailMessage: toolchainDetailMessage,
                    isPresented: $isToolStatusPresented
                ) {
                    viewModel.refreshToolchain()
                }
            }
        }
        .fileImporter(
            isPresented: $viewModel.isImporterPresented,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                Task { await analyzeImports(urls, source: .filePicker) }
            }
        }
        .sheet(isPresented: $isImportReviewPresented, onDismiss: {
            guard shouldClearImportReviewOnDismiss else { return }
            shouldClearImportReviewOnDismiss = false
            importReview.removeAll()
        }) {
            ImportReviewSheet(coordinator: importReview) {
                isImportReviewPresented = false
            } onConfirm: { items in
                confirmImports(items)
            }
            .environment(\.locale, selectedLanguage.locale)
        }
        .alert(item: $presentedAlert) { alert in
            switch alert {
            case .previewError(let message):
                Alert(
                    title: Text("Reader unavailable"),
                    message: Text(L10n.string(message)),
                    dismissButton: .default(Text("OK"))
                )
            case .deleteConfirmation(let task):
                Alert(
                    title: Text(deleteConfirmationTitle(for: task)),
                    message: Text(deleteConfirmationMessage(for: task)),
                    primaryButton: .destructive(Text("Delete")) {
                        deleteOutputFile(for: task)
                    },
                    secondaryButton: .cancel()
                )
            case .deletionError(let message):
                Alert(
                    title: Text("Couldn’t delete EPUB"),
                    message: Text(L10n.string(message)),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .overlay {
            if let readingPreparation {
                ReadingPreparationOverlay(preparation: readingPreparation)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else if importReview.isAnalyzing {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Analyzing book layout…").font(.headline)
                        Text("This happens locally on your Mac.").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(26)
                    .background(MobiPalette.sidebar, in: RoundedRectangle(cornerRadius: 18))
                    .shadow(radius: 18)
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: readingPreparation)
        .onChange(of: viewModel.tasks) { _, _ in
            updateReadingPreparation()
        }
        .onOpenURL { url in
            Task { await analyzeImports([url], source: .filePicker) }
        }
        .onChange(of: openBookRouter.request) { _, request in
            guard let request else { return }
            Task { await analyzeImports(request.urls, source: .filePicker) }
        }
        .onAppear {
            selectedAppearance.apply()
            if !importReview.items.isEmpty { isImportReviewPresented = true }
        }
        .onChange(of: appearanceRawValue) { _, _ in
            selectedAppearance.apply()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 8) {
                BrandMark()
                Text("MobiVerse")
                    .font(.system(size: 29, weight: .semibold, design: .serif))
                    .foregroundStyle(MobiPalette.ink)
                Text("Make room for every story")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(MobiPalette.terracotta)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)

            Picker("Workspace", selection: $workspace) {
                Label("Shelf", systemImage: "books.vertical").tag(AppWorkspace.library)
                Label("Browse", systemImage: "globe").tag(AppWorkspace.browser)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 18)

            Button {
                viewModel.isImporterPresented = true
            } label: {
                Label("Choose books", systemImage: "plus")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(MobiPalette.sage)

            if !importReview.items.isEmpty {
                Button {
                    isImportReviewPresented = true
                } label: {
                    Label(L10n.format("Review %lld imports", importReview.items.count), systemImage: "checklist")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
            }

            Button {
                viewModel.retryFailedTasks()
            } label: {
                Label("Retry failed", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(MobiPalette.ink.opacity(0.78))
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 12) {
                Text("Your shelf")
                    .font(.headline.weight(.semibold))

                SidebarMetric(value: viewModel.tasks.count, label: "Total conversions", icon: "books.vertical")
                SidebarMetric(value: completedTaskCount, label: "Succeeded", icon: "checkmark.circle.fill", color: MobiPalette.sage)
                SidebarMetric(value: failedTaskCount, label: "Failed", icon: "xmark.circle.fill", color: MobiPalette.terracotta)
                SidebarMetric(value: activeTaskCount, label: "In progress", icon: "progress.indicator", color: MobiPalette.cobalt)
            }
            .padding(.top, 24)

            Spacer()

            AppResourceImage(name: colorScheme == .dark ? "reading-still-life-dark" : "reading-still-life")
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 360, alignment: .bottom)
                // The dark asset has wider transparent safety margins for clean
                // antialiasing. Normalize its visible alpha bounds to the light asset.
                .scaleEffect(
                    x: colorScheme == .dark ? 1.46 : 1,
                    y: colorScheme == .dark ? 1.37 : 1,
                    anchor: .center
                )
                .padding(.horizontal, 4)
                .padding(.bottom, 12)
                .accessibilityHidden(true)

            HStack(spacing: 10) {
                Label(L10n.string(viewModel.canConvert ? "Ready to convert" : "Converter unavailable"), systemImage: viewModel.canConvert ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(viewModel.canConvert ? MobiPalette.sage : .orange)

                Spacer(minLength: 6)

                LanguageMenu(selectionRawValue: $languageRawValue)
                AppearanceMenu(selectionRawValue: $appearanceRawValue)
            }
        }
        .foregroundStyle(MobiPalette.ink)
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .background(MobiPalette.sidebar)
        .overlay(alignment: .trailing) { Divider() }
    }

    private var completedTaskCount: Int {
        viewModel.tasks.filter { $0.status == .succeeded || $0.status == .succeededWithWarnings }.count
    }

    private var selectedAppearance: AppAppearancePreference {
        AppAppearancePreference(rawValue: appearanceRawValue) ?? .system
    }

    private var selectedLanguage: AppLanguagePreference {
        AppLanguagePreference(rawValue: languageRawValue) ?? .simplifiedChinese
    }

    private var failedTaskCount: Int {
        viewModel.tasks.filter { $0.status == .failed }.count
    }

    private var activeTaskCount: Int {
        viewModel.tasks.filter { [.queued, .checkingTools, .converting, .validating].contains($0.status) }.count
    }

    private var toolchainDetailMessage: String {
        let calibreMessage = viewModel.toolchain.calibreSource == .bundled
            ? L10n.string("Using the Calibre copy packaged inside this app.")
            : L10n.string("Using the Calibre installation found on this Mac.")

        if viewModel.toolchain.epubCheckURL == nil {
            return L10n.format("%@ EPUBCheck was not found, so validation reports will be marked as skipped.", calibreMessage)
        } else {
            return L10n.format("%@ EPUBCheck is available. Converted EPUB files will be structurally validated.", calibreMessage)
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            dropZone
            taskList
        }
        .foregroundStyle(MobiPalette.ink)
        .background(MobiPalette.paper)
    }

    private var dropZone: some View {
        AppResourceImage(name: "hero-books-background")
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 250)
            .clipped()
            .overlay {
                if colorScheme == .dark {
                    Color.black.opacity(0.32)
                }
            }
            .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
                loadDroppedFiles(from: providers)
            return true
        }
    }

    private var dropTargetCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "book.closed")
                .font(.system(size: 31, weight: .medium))
            Text("Drop books here")
                .font(.system(size: 27, weight: .semibold, design: .serif))
            Text("EPUB, MOBI, AZW, AZW3, CBZ, CBR, ZIP, or PDF")
                .font(.callout)
            Text("EPUB opens instantly. Other books convert, then open for reading.")
                .font(.caption)
                .foregroundStyle(MobiPalette.ink.opacity(0.58))
        }
        .foregroundStyle(MobiPalette.ink)
        .frame(maxWidth: 540)
        .frame(height: 190)
        .padding(.horizontal, 34)
        .background(MobiPalette.cream.opacity(0.80), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.94), style: StrokeStyle(lineWidth: 1.6, dash: [8, 6]))
        }
        .shadow(color: MobiPalette.ink.opacity(0.18), radius: 22, y: 10)
        .padding(.horizontal, 190)
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string(taskLayout == .shelf3D ? "Your shelf" : "Ready"))
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                Spacer()
                TaskLayoutToggle(selectedLayout: $taskLayout)
            }
            .padding(.horizontal, 30)
            .padding(.top, 18)

            if taskLayout == .shelf3D {
                Shelf3DView(
                    tasks: shelfTasks,
                    coverImage: { task in
                        viewModel.showcaseCoverImage(for: task) ?? viewModel.coverImage(for: task)
                    },
                    metadata: viewModel.metadata(for:),
                    isOutputMissing: viewModel.isOutputMissing(for:),
                    requestAssets: viewModel.requestShelfAssets(for:),
                    addBooks: { viewModel.isImporterPresented = true },
                    preview: preview,
                    revealOutput: viewModel.revealOutput(for:),
                    openReport: viewModel.openReport(for:),
                    deleteOutput: { task in presentedAlert = .deleteConfirmation(task) }
                )
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
                .transition(.opacity.combined(with: .scale(scale: 0.992)))
            } else {
                ScrollView {
                    LazyVGrid(columns: taskGridColumns, spacing: 14) {
                        ForEach(shelfTasks) { task in
                            TaskRow(
                                task: task,
                                coverImage: viewModel.coverImage(for: task),
                                isOutputMissing: viewModel.isOutputMissing(for: task),
                                canDelete: viewModel.canDelete(task)
                            ) {
                                preview(task)
                            } revealOutput: {
                                viewModel.revealOutput(for: task)
                            } openReport: {
                                viewModel.openReport(for: task)
                            } deleteOutput: {
                                presentedAlert = .deleteConfirmation(task)
                            }
                            .onAppear {
                                viewModel.requestCoverImage(for: task)
                            }
                        }

                        AddBookShelfCard {
                            viewModel.isImporterPresented = true
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
                }
                .overlay {
                    if viewModel.tasks.isEmpty {
                        ContentUnavailableView(
                            "Your shelf is empty",
                            systemImage: "books.vertical",
                            description: Text("Add a book above to begin your MobiVerse library.")
                        )
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: taskLayout)
    }

    private var shelfTasks: [ConversionTask] {
        viewModel.tasks.enumerated()
            .sorted { lhs, rhs in
                let lhsPriority = shelfPriority(for: lhs.element.status)
                let rhsPriority = shelfPriority(for: rhs.element.status)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }

                if lhsPriority < 2 {
                    return lhs.offset < rhs.offset
                }

                let lhsDate = lhs.element.completedAt ?? .distantPast
                let rhsDate = rhs.element.completedAt ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.offset < rhs.offset
            }
            .map { $0.element }
    }

    private func shelfPriority(for status: ConversionStatus) -> Int {
        switch status {
        case .checkingTools, .converting, .validating:
            0
        case .queued:
            1
        case .succeeded, .succeededWithWarnings, .failed:
            2
        }
    }

    private var taskGridColumns: [GridItem] {
        switch taskLayout {
        case .grid:
            [GridItem(.adaptive(minimum: 340, maximum: 560), spacing: 14)]
        case .list:
            [GridItem(.flexible(minimum: 340), spacing: 14)]
        case .shelf3D:
            [GridItem(.flexible(minimum: 340), spacing: 14)]
        }
    }

    private var allowedContentTypes: [UTType] {
        let conversionTypes = SupportedInputFormat.all.compactMap { UTType(filenameExtension: $0.fileExtension) }
        return conversionTypes + [UTType(filenameExtension: "epub")].compactMap { $0 }
    }

    private func loadDroppedFiles(from providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard
                    let data = item as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                else {
                    return
                }

                Task { @MainActor in
                    await analyzeImports([url], source: .dragAndDrop)
                }
            }
        }
    }

    private func preview(_ task: ConversionTask) {
        guard let outputURL = task.outputURL else { return }
        openEpubPreview(outputURL)
    }

    @MainActor
    private func analyzeImports(_ urls: [URL], source: ImportSource) async {
        let supported = urls.filter {
            isEpub($0) || viewModel.acceptedExtensions.contains($0.pathExtension.lowercased())
        }
        guard !supported.isEmpty else { return }
        await importReview.analyze(
            urls: supported,
            source: source,
            ebookConvertURL: viewModel.toolchain.ebookConvertURL
        )
        isImportReviewPresented = !importReview.items.isEmpty
    }

    private func confirmImports(_ items: [PendingImport]) {
        let convertable = items.compactMap { item -> ReviewedImport? in
            guard !item.isEPUB, let profile = item.selectedProfile else { return nil }
            return ReviewedImport(
                url: item.url,
                source: item.source,
                detectedKind: item.classification.kind,
                profile: profile,
                readingDirection: item.readingDirection
            )
        }
        _ = viewModel.addReviewedFiles(convertable)
        let epubs = items.filter(\.isEPUB)
        for item in epubs { viewModel.addEpubToLibrary(item.url) }
        if let firstEPUB = epubs.first?.url {
            openEpubPreview(firstEPUB)
        }
        shouldClearImportReviewOnDismiss = true
        isImportReviewPresented = false
        workspace = .library
    }

    private func updateReadingPreparation() {
        guard
            let preparation = readingPreparation,
            let taskID = preparation.taskID,
            let task = viewModel.task(withID: taskID)
        else {
            return
        }

        switch task.status {
        case .queued, .checkingTools, .converting, .validating:
            readingPreparation = preparation.updated(
                message: readingMessage(for: task),
                progress: task.progress
            )
        case .succeeded, .succeededWithWarnings:
            guard let outputURL = task.outputURL, !viewModel.isOutputMissing(for: task) else {
                readingPreparation = nil
                presentedAlert = .previewError(L10n.string("The converted EPUB is no longer available at the saved output path."))
                return
            }
            readingPreparation = ReadingPreparation(
                sourceTitle: preparation.sourceTitle,
                message: "Opening EPUB preview",
                progress: 1
            )
            openEpubPreview(outputURL)
        case .failed:
            readingPreparation = nil
            presentedAlert = .previewError(task.statusMessage)
        }
    }

    private func readingMessage(for task: ConversionTask) -> String {
        switch task.status {
        case .queued:
            "Preparing conversion"
        case .checkingTools:
            "Checking conversion tools"
        case .converting:
            "Converting to EPUB"
        case .validating:
            "Finalizing EPUB"
        case .succeeded, .succeededWithWarnings:
            "Opening EPUB preview"
        case .failed:
            task.statusMessage
        }
    }

    private func isEpub(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "epub"
    }

    private func openEpubPreview(_ outputURL: URL, addToLibrary: Bool = false) {
        let extractionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MobiVersePreview", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        Task {
            do {
                let book = try await EpubPreviewParser().parse(
                    epubURL: outputURL,
                    extractionDirectory: extractionDirectory
                )
                await MainActor.run {
                    if addToLibrary {
                        viewModel.addEpubToLibrary(outputURL)
                    }
                    previewWindowController?.close()
                    let controller = EpubPreviewWindowController(book: book)
                    controller.onClose = {
                        previewWindowController = nil
                    }
                    previewWindowController = controller
                    controller.show()
                    readingPreparation = nil
                }
            } catch let error as EpubPreviewParserError {
                try? FileManager.default.removeItem(at: extractionDirectory)
                await MainActor.run {
                    readingPreparation = nil
                    presentedAlert = .previewError(error.message)
                }
            } catch {
                try? FileManager.default.removeItem(at: extractionDirectory)
                await MainActor.run {
                    readingPreparation = nil
                    presentedAlert = .previewError(error.localizedDescription)
                }
            }
        }
    }

    private func deleteConfirmationMessage(for task: ConversionTask) -> String {
        guard let outputURL = task.outputURL, FileManager.default.fileExists(atPath: outputURL.path) else {
            return L10n.string("This conversion will be removed from your history. No local EPUB file is available to delete.")
        }
        return L10n.format("\"%@\" will be permanently deleted from this Mac, and this conversion will be removed from your history.", outputURL.lastPathComponent)
    }

    private func deleteConfirmationTitle(for task: ConversionTask) -> String {
        guard let outputURL = task.outputURL, FileManager.default.fileExists(atPath: outputURL.path) else {
            return L10n.string("Remove conversion history?")
        }
        return L10n.string("Delete local EPUB?")
    }

    private func deleteOutputFile(for task: ConversionTask) {
        do {
            try viewModel.deleteTaskAndOutputFile(task)
        } catch {
            DispatchQueue.main.async {
                presentedAlert = .deletionError(error.localizedDescription)
            }
        }
    }
}

private enum ContentAlert: Identifiable {
    case previewError(String)
    case deleteConfirmation(ConversionTask)
    case deletionError(String)

    var id: String {
        switch self {
        case .previewError(let message):
            "preview-\(message)"
        case .deleteConfirmation(let task):
            "delete-\(task.id.uuidString)"
        case .deletionError(let message):
            "deletion-error-\(message)"
        }
    }
}

private struct AppResourceImage: View {
    let name: String

    var body: some View {
        if let image = loadImage() {
            Image(nsImage: image)
                .resizable()
        } else {
            Color.clear
        }
    }

    private func loadImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        let resourceBundleName = "Mobi2EpubTransfer_Mobi2EpubTransfer.bundle"
        let bundleURLs = [
            Bundle.main.bundleURL.appendingPathComponent(resourceBundleName, isDirectory: true),
            Bundle.main.resourceURL?.appendingPathComponent(resourceBundleName, isDirectory: true),
            Bundle.main.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent(resourceBundleName, isDirectory: true)
        ].compactMap { $0 }

        for bundleURL in bundleURLs {
            guard
                let resourceBundle = Bundle(url: bundleURL),
                let imageURL = resourceBundle.url(forResource: name, withExtension: "png"),
                let image = NSImage(contentsOf: imageURL)
            else {
                continue
            }
            return image
        }

        return nil
    }
}

private struct BrandMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(MobiPalette.ink)
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(MobiPalette.cream)
                .offset(x: 10, y: -12)
            Image(systemName: "book.closed.fill")
                .font(.system(size: 27, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(MobiPalette.terracotta, MobiPalette.cream)
            Image(systemName: "leaf.fill")
                .font(.system(size: 17))
                .foregroundStyle(MobiPalette.sage)
                .offset(x: -31, y: 18)
        }
        .frame(width: 72, height: 72)
    }
}

private struct SidebarMetric: View {
    let value: Int
    let label: String
    let icon: String
    var color: Color = MobiPalette.ink.opacity(0.72)

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)
            Text(L10n.string(label))
                .font(.callout)
            Spacer()
            Text(value.formatted())
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct AppearanceMenu: View {
    @Binding var selectionRawValue: String

    private var selection: AppAppearancePreference {
        AppAppearancePreference(rawValue: selectionRawValue) ?? .system
    }

    var body: some View {
        Menu {
            ForEach(AppAppearancePreference.allCases) { option in
                Button {
                    selectionRawValue = option.rawValue
                } label: {
                    Label(option.title, systemImage: selection == option ? "checkmark" : option.icon)
                }
            }
        } label: {
            Image(systemName: selection.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MobiPalette.ink.opacity(0.72))
                .frame(width: 27, height: 27)
                .background(MobiPalette.surface.opacity(0.72), in: Circle())
                .overlay {
                    Circle().stroke(MobiPalette.ink.opacity(0.10), lineWidth: 1)
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.format("Appearance: %@", selection.title))
        .accessibilityLabel(L10n.string("Appearance"))
        .accessibilityValue(selection.title)
    }
}

private struct LanguageMenu: View {
    @Binding var selectionRawValue: String

    private var selection: AppLanguagePreference {
        AppLanguagePreference(rawValue: selectionRawValue) ?? .simplifiedChinese
    }

    var body: some View {
        Menu {
            ForEach(AppLanguagePreference.allCases) { option in
                Button {
                    selectionRawValue = option.rawValue
                } label: {
                    Label(option.title, systemImage: selection == option ? "checkmark" : "globe")
                }
            }
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MobiPalette.ink.opacity(0.72))
                .frame(width: 27, height: 27)
                .background(MobiPalette.surface.opacity(0.72), in: Circle())
                .overlay {
                    Circle().stroke(MobiPalette.ink.opacity(0.10), lineWidth: 1)
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.format("Language: %@", selection.title))
        .accessibilityLabel(L10n.string("Language"))
        .accessibilityValue(selection.title)
    }
}

private struct DecorativeBook: View {
    let color: Color
    let rotation: Double
    let motif: String

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color)
            .frame(width: 112, height: 176)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.22))
                VStack(spacing: 12) {
                    Image(systemName: motif)
                        .font(.system(size: 31, weight: .light))
                    Rectangle()
                        .frame(width: 34, height: 1)
                }
                .foregroundStyle(MobiPalette.ink.opacity(0.34))
            }
            .shadow(color: .black.opacity(0.24), radius: 10, y: 7)
            .rotationEffect(.degrees(rotation))
    }
}

private struct FormatPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.35)
            .foregroundStyle(MobiPalette.ink.opacity(0.65))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(MobiPalette.ink.opacity(0.055), in: Capsule())
    }
}

private struct ReadingPreparation: Identifiable, Equatable {
    let id = UUID()
    let taskID: UUID?
    let sourceTitle: String
    let message: String
    let progress: Double?

    init(taskID: UUID? = nil, sourceTitle: String, message: String, progress: Double?) {
        self.taskID = taskID
        self.sourceTitle = sourceTitle
        self.message = message
        self.progress = progress
    }

    func updated(message: String, progress: Double?) -> ReadingPreparation {
        ReadingPreparation(taskID: taskID, sourceTitle: sourceTitle, message: message, progress: progress)
    }
}

private struct ReadingPreparationOverlay: View {
    let preparation: ReadingPreparation

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.18))
                .ignoresSafeArea()

            VStack(spacing: 18) {
                AnimatedSVGPreparationView()
                    .frame(width: 148, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(spacing: 6) {
                    Text(L10n.string(preparation.message))
                        .font(.headline)
                    Text(preparation.sourceTitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 300)
                }

                if let progress = preparation.progress {
                    ProgressView(value: min(max(progress, 0), 1))
                        .progressViewStyle(.linear)
                        .frame(width: 260)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 30, y: 18)
        }
    }
}

private struct AnimatedSVGPreparationView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.loadHTMLString(svgHTML, baseURL: nil)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    private var svgHTML: String {
        """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: transparent; }
          svg { width: 100%; height: 100%; display: block; }
          .page { transform-origin: 45px 60px; animation: turn 1.8s ease-in-out infinite; }
          .spark { animation: pulse 1.8s ease-in-out infinite; }
          .spark.two { animation-delay: .28s; }
          .spark.three { animation-delay: .56s; }
          .line { stroke-dasharray: 44; stroke-dashoffset: 44; animation: write 1.8s ease-in-out infinite; }
          @keyframes turn {
            0%, 18% { transform: rotateY(0deg) translateX(0); opacity: 1; }
            54% { transform: rotateY(-58deg) translateX(12px); opacity: .92; }
            78%, 100% { transform: rotateY(0deg) translateX(0); opacity: 1; }
          }
          @keyframes pulse {
            0%, 100% { opacity: .25; transform: scale(.85); }
            42% { opacity: 1; transform: scale(1); }
          }
          @keyframes write {
            0%, 18% { stroke-dashoffset: 44; }
            56%, 100% { stroke-dashoffset: 0; }
          }
        </style>
        </head>
        <body>
        <svg viewBox="0 0 148 112" fill="none" xmlns="http://www.w3.org/2000/svg">
          <rect width="148" height="112" rx="18" fill="#F8FAFC"/>
          <path d="M24 28c0-4.4 3.6-8 8-8h31c5.5 0 10 4.5 10 10v58c0 2.2-1.8 4-4 4H34c-5.5 0-10-4.5-10-10V28Z" fill="#EAF4FF" stroke="#1764D8" stroke-width="3"/>
          <path class="page" d="M42 22h32c5.5 0 10 4.5 10 10v58H50c-4.4 0-8-3.6-8-8V22Z" fill="white" stroke="#1764D8" stroke-width="3"/>
          <path class="line" d="M54 42h20M54 56h20M54 70h14" stroke="#1CB7A6" stroke-width="4" stroke-linecap="round"/>
          <path d="M91 56h23" stroke="#94A3B8" stroke-width="4" stroke-linecap="round"/>
          <path d="M109 45l12 11-12 11" stroke="#94A3B8" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>
          <rect x="105" y="25" width="27" height="62" rx="5" fill="#111827"/>
          <rect x="111" y="35" width="15" height="28" rx="2" fill="#F8FAFC"/>
          <text x="118.5" y="78" text-anchor="middle" fill="#F8FAFC" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="9" font-weight="700">EPUB</text>
          <circle class="spark" cx="99" cy="24" r="3" fill="#1CB7A6"/>
          <circle class="spark two" cx="128" cy="18" r="3" fill="#1764D8"/>
          <circle class="spark three" cx="137" cy="91" r="3" fill="#1CB7A6"/>
        </svg>
        </body>
        </html>
        """
    }
}

@MainActor
private final class EpubPreviewWindowState: ObservableObject {
    @Published var isFullScreen = false
}

@MainActor
private final class PreviewGestureRouter: ObservableObject {
    var canMoveBackward = false
    var canMoveForward = false
    var handleSwipeChanged: ((Double) -> Void)?
    var handleSwipeEnded: ((Double) -> Void)?
    var zoomBy: ((Double) -> Void)?
    var moveBackward: (() -> Void)?
    var moveForward: (() -> Void)?
    var toggleChrome: (() -> Void)?

    private var horizontalSwipeDelta = 0.0
    private var isTrackingHorizontalSwipe = false
    private var swipeEndWorkItem: DispatchWorkItem?
    private let swipeEndFallbackDelay = 0.08

    func resetHandlers() {
        canMoveBackward = false
        canMoveForward = false
        handleSwipeChanged = nil
        handleSwipeEnded = nil
        zoomBy = nil
        moveBackward = nil
        moveForward = nil
        toggleChrome = nil
        finishHorizontalSwipe()
    }

    func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .magnify:
            zoomBy?(Double(event.magnification) * 1.8)
            return nil
        case .swipe:
            guard handleSwipeChanged != nil, handleSwipeEnded != nil else {
                return event
            }
            handleSwipeEvent(event)
            return nil
        case .scrollWheel:
            return handleScrollWheelEvent(event) ? nil : event
        case .keyDown:
            return handleKeyDownEvent(event) ? nil : event
        default:
            return event
        }
    }

    func handleScrollWheel(_ event: NSEvent) -> Bool {
        handleScrollWheelEvent(event)
    }

    func handleMagnify(_ event: NSEvent) {
        zoomBy?(Double(event.magnification) * 1.8)
    }

    func handleSwipe(_ event: NSEvent) {
        handleSwipeEvent(event)
    }

    private func handleKeyDownEvent(_ event: NSEvent) -> Bool {
        guard moveBackward != nil || moveForward != nil else { return false }
        let unsupportedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(unsupportedModifiers).isEmpty else { return false }

        switch event.keyCode {
        case 49:
            toggleChrome?()
            return toggleChrome != nil
        case 123:
            if canMoveBackward {
                moveBackward?()
            }
            return true
        case 124:
            if canMoveForward {
                moveForward?()
            }
            return true
        default:
            return false
        }
    }

    private func handleScrollWheelEvent(_ event: NSEvent) -> Bool {
        guard handleSwipeChanged != nil, handleSwipeEnded != nil else {
            return false
        }
        guard isTrackingHorizontalSwipe || isHorizontalPageSwipe(event) else {
            return false
        }

        if isTrackingHorizontalSwipe && (event.momentumPhase == .began || event.momentumPhase == .changed) {
            finishHorizontalSwipe()
            return true
        }

        switch event.phase {
        case .began, .mayBegin:
            beginHorizontalSwipe()
            updateHorizontalSwipe(with: event)
        case .changed:
            updateHorizontalSwipe(with: event)
        case .ended, .cancelled:
            finishHorizontalSwipe()
        default:
            if event.momentumPhase == .ended || event.momentumPhase == .cancelled {
                finishHorizontalSwipe()
            } else {
                updateHorizontalSwipe(with: event)
            }
        }
        return true
    }

    private func handleSwipeEvent(_ event: NSEvent) {
        let syntheticDelta = event.deltaX > 0 ? -220.0 : 220.0
        handleSwipeChanged?(syntheticDelta)
        handleSwipeEnded?(syntheticDelta)
    }

    private func isHorizontalPageSwipe(_ event: NSEvent) -> Bool {
        guard event.hasPreciseScrollingDeltas else { return false }
        let horizontal = abs(event.scrollingDeltaX)
        let vertical = abs(event.scrollingDeltaY)
        return horizontal > vertical * 1.25 && horizontal > 2
    }

    private func beginHorizontalSwipe() {
        isTrackingHorizontalSwipe = true
        horizontalSwipeDelta = 0
        swipeEndWorkItem?.cancel()
    }

    private func updateHorizontalSwipe(with event: NSEvent) {
        guard isTrackingHorizontalSwipe || isHorizontalPageSwipe(event) else { return }
        if !isTrackingHorizontalSwipe {
            beginHorizontalSwipe()
        }

        horizontalSwipeDelta -= Double(event.scrollingDeltaX)
        handleSwipeChanged?(horizontalSwipeDelta)
        scheduleSwipeEndFallback()
    }

    private func finishHorizontalSwipe() {
        swipeEndWorkItem?.cancel()
        swipeEndWorkItem = nil
        guard isTrackingHorizontalSwipe else { return }
        handleSwipeEnded?(horizontalSwipeDelta)
        horizontalSwipeDelta = 0
        isTrackingHorizontalSwipe = false
    }

    private func scheduleSwipeEndFallback() {
        swipeEndWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishHorizontalSwipe()
        }
        swipeEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + swipeEndFallbackDelay, execute: workItem)
    }
}

@MainActor
private final class PreviewHostingView<Content: View>: NSHostingView<Content> {
    let gestureRouter: PreviewGestureRouter

    init(rootView: Content, gestureRouter: PreviewGestureRouter) {
        self.gestureRouter = gestureRouter
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init(rootView: Content) {
        fatalError("init(rootView:) has not been implemented")
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func scrollWheel(with event: NSEvent) {
        if !gestureRouter.handleScrollWheel(event) {
            super.scrollWheel(with: event)
        }
    }

    override func magnify(with event: NSEvent) {
        gestureRouter.handleMagnify(event)
    }

    override func swipe(with event: NSEvent) {
        gestureRouter.handleSwipe(event)
    }
}

@MainActor
private final class EpubPreviewWindowController: NSWindowController, NSWindowDelegate {
    let book: EpubPreviewBook
    var onClose: (() -> Void)?
    private let windowState = EpubPreviewWindowState()
    private let gestureRouter = PreviewGestureRouter()
    private let readingPositionStore = PreviewReadingPositionStore()
    private var eventMonitor: Any?

    init(book: EpubPreviewBook) {
        self.book = book
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = book.title
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.minSize = NSSize(width: 780, height: 620)
        super.init(window: window)
        window.delegate = self
        let legacyInterpretation: LegacyReadingPositionInterpretation = switch book.mode {
        case .imagePages: .page
        case .web: .section
        }
        let initialPosition = readingPositionStore.position(
            for: book.epubURL,
            legacyInterpretation: legacyInterpretation
        ) ?? PreviewReadingPosition(sectionIndex: 0, pageIndex: 0)
        window.contentView = PreviewHostingView(
            rootView: EpubPreviewView(
                book: book,
                windowState: windowState,
                gestureRouter: gestureRouter,
                initialPosition: initialPosition,
                savePosition: { [readingPositionStore, epubURL = book.epubURL] position in
                    readingPositionStore.save(position: position, for: epubURL)
                },
                toggleFullScreen: { [weak window] in
                    guard let window else { return }
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async {
                        window.toggleFullScreen(nil)
                    }
                },
                close: { [weak window] in
                    window?.close()
                }
            )
            .environment(\.locale, AppLanguagePreference.selected.locale),
            gestureRouter: gestureRouter
        )
        installEventMonitor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        gestureRouter.resetHandlers()
        try? FileManager.default.removeItem(at: book.extractionDirectory)
        onClose?()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        windowState.isFullScreen = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        windowState.isFullScreen = false
    }

    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify, .swipe, .keyDown]) { [weak self] event in
            guard
                let self,
                let window = self.window,
                event.window === window || window.isKeyWindow
            else {
                return event
            }
            return self.gestureRouter.handle(event)
        }
    }
}

private struct ToolStatusButton: View {
    let toolchain: ToolchainAvailability
    let canConvert: Bool
    let missingToolsMessage: String?
    let detailMessage: String
    @Binding var isPresented: Bool
    let refresh: () -> Void

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
        }
        .buttonStyle(.borderless)
        .help("Conversion tools")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: iconName)
                        .font(.title3)
                        .foregroundStyle(iconColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.string(canConvert ? toolchain.calibreSource.displayName : "Calibre missing"))
                            .font(.headline)
                        Text(L10n.string(epubCheckSummary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(L10n.string(missingToolsMessage ?? detailMessage))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button {
                        refresh()
                    } label: {
                        Label(L10n.string("Refresh"), systemImage: "arrow.triangle.2.circlepath")
                    }

                    Spacer()
                }
                .controlSize(.small)
            }
            .padding(16)
            .frame(width: 320)
        }
    }

    private var iconName: String {
        if !canConvert {
            return "exclamationmark.triangle.fill"
        }
        return toolchain.epubCheckURL == nil ? "checkmark.circle" : "checkmark.seal.fill"
    }

    private var iconColor: Color {
        if !canConvert {
            return .orange
        }
        return toolchain.epubCheckURL == nil ? .secondary : .green
    }

    private var epubCheckSummary: String {
        toolchain.epubCheckURL == nil ? "EPUBCheck not bundled" : "EPUBCheck available"
    }
}

private struct AddBookShelfCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(MobiPalette.sage.opacity(0.65))
                Text("Add more books")
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                Text("Drag and drop or choose files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 132)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(MobiPalette.ink)
        .background(MobiPalette.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(MobiPalette.ink.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [7, 6]))
        }
    }
}

private enum AppWorkspace: Hashable {
    case library
    case browser
}

private enum TaskLayout: Hashable {
    case grid
    case list
    case shelf3D
}

private struct TaskLayoutToggle: View {
    @Binding var selectedLayout: TaskLayout

    var body: some View {
        HStack(spacing: 2) {
            layoutButton(layout: .grid, icon: "square.grid.2x2.fill", title: "Grid view")
            layoutButton(layout: .list, icon: "list.bullet", title: "List view")
            layoutButton(layout: .shelf3D, icon: "books.vertical.fill", title: "3D shelf")
        }
        .font(.callout)
        .padding(5)
        .background(MobiPalette.surface.opacity(0.90), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(MobiPalette.ink.opacity(0.06))
        }
    }

    private func layoutButton(layout: TaskLayout, icon: String, title: String) -> some View {
        Button {
            selectedLayout = layout
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 30)
                .foregroundStyle(selectedLayout == layout ? MobiPalette.sage : MobiPalette.ink.opacity(0.24))
                .background {
                    if selectedLayout == layout {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(MobiPalette.surfaceRaised)
                            .shadow(color: MobiPalette.ink.opacity(0.08), radius: 3, y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(L10n.string(title))
        .accessibilityLabel(L10n.string(title))
        .accessibilityAddTraits(selectedLayout == layout ? .isSelected : [])
    }
}

private struct TaskRow: View {
    let task: ConversionTask
    let coverImage: NSImage?
    let isOutputMissing: Bool
    let canDelete: Bool
    let preview: () -> Void
    let revealOutput: () -> Void
    let openReport: () -> Void
    let deleteOutput: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                coverThumbnail

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(task.inputURL.deletingPathExtension().lastPathComponent)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        if isOutputMissing { MissingFileBadge() } else { StatusBadge(status: task.status) }
                    }

                    Text(completionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    ProgressView(value: task.progress)
                        .progressViewStyle(.linear)
                        .tint(accentColor)
                        .opacity(isOutputMissing ? 0.3 : 0.85)
                }
                .frame(height: 86)
            }

            HStack(spacing: 7) {
                TaskActionButton(title: "Read", icon: "book.pages", enabled: canPreview, showsTitle: true, action: preview)
                TaskActionButton(title: "Reveal", icon: "folder", enabled: task.outputURL != nil && !isOutputMissing, showsTitle: true, action: revealOutput)
                TaskActionButton(title: "Report", icon: "doc.text", enabled: task.reportURL != nil, showsTitle: true, action: openReport)
                TaskActionButton(title: "Delete EPUB", icon: "trash", enabled: canDelete, role: .destructive, action: deleteOutput)
            }
        }
        .padding(14)
        .background(MobiPalette.surface.opacity(0.90), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(MobiPalette.ink.opacity(0.055))
        }
        .shadow(color: MobiPalette.ink.opacity(0.045), radius: 12, y: 5)
        .opacity(isOutputMissing ? 0.48 : 1)
    }

    private var canPreview: Bool {
        !isOutputMissing && (task.status == .succeeded || task.status == .succeededWithWarnings) && task.outputURL != nil
    }

    private var accentColor: Color {
        switch task.status {
        case .failed: MobiPalette.coral
        case .succeededWithWarnings: .orange
        case .succeeded: MobiPalette.mint
        case .queued, .checkingTools, .converting, .validating: MobiPalette.cobalt
        }
    }

    private var coverColor: Color {
        switch task.inputURL.pathExtension.lowercased() {
        case "azw", "azw3": MobiPalette.cobalt
        case "mobi": MobiPalette.sage
        case "cbz", "cbr", "zip", "pdf": MobiPalette.terracotta
        default: MobiPalette.walnut
        }
    }

    @ViewBuilder
    private var coverThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(coverColor)

            if let coverImage {
                Image(nsImage: coverImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 62, height: 86)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        LinearGradient(
                            colors: [.black.opacity(0.08), .clear, .black.opacity(0.16)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
            } else {
                Image(systemName: formatIcon)
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(.white.opacity(0.82))
                Text(task.inputURL.pathExtension.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(y: 29)
            }
        }
        .frame(width: 62, height: 86)
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.white.opacity(0.55), lineWidth: 0.8)
        }
        .shadow(color: MobiPalette.ink.opacity(0.13), radius: 6, y: 3)
    }

    private var completionText: String {
        if isOutputMissing { return "Converted EPUB is no longer available" }
        if let completedAt = task.completedAt {
            return L10n.format("Completed %@", completedAt.formatted(date: .abbreviated, time: .shortened))
        }
        return L10n.string(task.statusMessage)
    }

    private var formatIcon: String {
        switch task.inputURL.pathExtension.lowercased() {
        case "cbz", "cbr", "zip", "pdf": "photo.on.rectangle.angled"
        default: "book.closed.fill"
        }
    }
}

private struct TaskActionButton: View {
    let title: String
    let icon: String
    let enabled: Bool
    var role: ButtonRole?
    var showsTitle = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                if showsTitle { Text(L10n.string(title)) }
            }
            .font(.caption.weight(.medium))
            .frame(maxWidth: showsTitle ? .infinity : nil)
            .frame(height: 32)
            .padding(.horizontal, showsTitle ? 7 : 9)
            .foregroundStyle(role == .destructive ? MobiPalette.coral : MobiPalette.ink.opacity(0.65))
            .background(MobiPalette.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.3)
        .disabled(!enabled)
        .help(L10n.string(title))
    }
}

private struct EpubPreviewView: View {
    let book: EpubPreviewBook
    @ObservedObject var windowState: EpubPreviewWindowState
    let gestureRouter: PreviewGestureRouter
    let initialPosition: PreviewReadingPosition
    let savePosition: (PreviewReadingPosition) -> Void
    let toggleFullScreen: () -> Void
    let close: () -> Void
    @State private var isChromeVisible = true
    @State private var chromeHideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            switch book.mode {
            case .imagePages(let pages):
                ComicImagePreview(
                    pages: pages,
                    readingDirection: book.readingDirection,
                    gestureRouter: gestureRouter,
                    initialPageIndex: initialPosition.pageIndex,
                    isChromeVisible: isChromeVisible,
                    savePageIndex: { pageIndex in
                        savePosition(PreviewReadingPosition(sectionIndex: 0, pageIndex: pageIndex))
                    }
                )
            case .web(let spineURLs):
                TextEpubPreview(
                    spineURLs: spineURLs,
                    readAccessURL: book.contentRootDirectory,
                    readingDirection: book.readingDirection,
                    gestureRouter: gestureRouter,
                    initialPosition: initialPosition,
                    isChromeVisible: isChromeVisible,
                    savePosition: savePosition
                )
            }

            if isChromeVisible {
                readerHeader
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color.black)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                revealChrome()
            case .ended:
                scheduleChromeHide()
            }
        }
        .onAppear {
            gestureRouter.toggleChrome = toggleChrome
            scheduleChromeHide()
        }
        .onDisappear {
            chromeHideTask?.cancel()
            gestureRouter.toggleChrome = nil
        }
        .onChange(of: windowState.isFullScreen) { _, _ in
            revealChrome()
        }
        .onChange(of: isChromeVisible) { _, visible in
            if !visible {
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }

    private var readerHeader: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MobiPalette.cream.opacity(0.76))
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MobiPalette.sage)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(book.title)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(MobiPalette.ink)
                    .lineLimit(1)
                Text(modeLabel)
                    .font(.caption2)
                    .foregroundStyle(MobiPalette.ink.opacity(0.54))
            }

            Spacer(minLength: 20)

            readerHeaderButton(
                title: fullScreenButtonLabel,
                icon: fullScreenButtonIcon,
                action: toggleFullScreen
            )
            readerHeaderButton(title: "Close Reader", icon: "xmark", action: close)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.20), radius: 18, y: 8)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func readerHeaderButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(MobiPalette.ink.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(MobiPalette.ink.opacity(0.74))
        .help(L10n.string(title))
        .accessibilityLabel(L10n.string(title))
    }

    private var modeLabel: String {
        switch book.mode {
        case .imagePages(let pages):
            L10n.format("%lld image pages", pages.count)
        case .web(let spineURLs):
            L10n.format("Text EPUB · %lld sections", spineURLs.count)
        }
    }

    private var fullScreenButtonLabel: String {
        L10n.string(windowState.isFullScreen ? "Exit full screen" : "Enter full screen")
    }

    private var fullScreenButtonIcon: String {
        windowState.isFullScreen
            ? "arrow.down.right.and.arrow.up.left"
            : "arrow.up.left.and.arrow.down.right"
    }

    private func toggleChrome() {
        chromeHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.20)) {
            isChromeVisible.toggle()
        }
        if isChromeVisible {
            scheduleChromeHide()
        }
    }

    private func revealChrome() {
        chromeHideTask?.cancel()
        if !isChromeVisible {
            withAnimation(.easeOut(duration: 0.18)) {
                isChromeVisible = true
            }
        }
        scheduleChromeHide()
    }

    private func scheduleChromeHide() {
        chromeHideTask?.cancel()
        chromeHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.28)) {
                isChromeVisible = false
            }
        }
    }
}

private enum ComicReadingMode: String, CaseIterable, Identifiable {
    case single
    case spread
    case continuous

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: L10n.string("Single page")
        case .spread: L10n.string("Two-page spread")
        case .continuous: L10n.string("Continuous scroll")
        }
    }

    var icon: String {
        switch self {
        case .single: "rectangle.portrait"
        case .spread: "book.pages"
        case .continuous: "rectangle.stack"
        }
    }
}

private struct ComicPageUnit: Identifiable {
    let id: Int
    let pageIndices: [Int]
}

@MainActor
private final class EpubPreviewImageCache {
    static let shared = EpubPreviewImageCache()

    private let images = NSCache<NSURL, NSImage>()
    private let edgeColors = NSCache<NSURL, NSColor>()
    private var dataLoads: [URL: Task<Data?, Never>] = [:]

    func image(for url: URL) async -> NSImage? {
        if let cached = images.object(forKey: url as NSURL) {
            return cached
        }

        let load: Task<Data?, Never>
        if let existing = dataLoads[url] {
            load = existing
        } else {
            load = Task.detached(priority: .utility) {
                try? Data(contentsOf: url, options: [.mappedIfSafe])
            }
            dataLoads[url] = load
        }

        let data = await load.value
        dataLoads[url] = nil
        guard let data, let image = NSImage(data: data) else { return nil }
        images.setObject(image, forKey: url as NSURL)
        return image
    }

    func prefetch(_ urls: [URL]) async {
        for url in urls {
            _ = await image(for: url)
        }
    }

    func canvasColor(for url: URL) async -> Color {
        if let cached = edgeColors.object(forKey: url as NSURL) {
            return Color(nsColor: cached)
        }
        guard let image = await image(for: url), let sampled = sampleEdgeTint(from: image) else {
            return Color(red: 0.045, green: 0.055, blue: 0.06)
        }
        edgeColors.setObject(sampled, forKey: url as NSURL)
        return Color(nsColor: sampled)
    }

    private func sampleEdgeTint(from image: NSImage) -> NSColor? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 24,
            pixelsHigh: 24,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: 24, height: 24))
        NSGraphicsContext.restoreGraphicsState()

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var count = 0.0
        for index in 0..<24 {
            for point in [(index, 0), (index, 23), (0, index), (23, index)] {
                guard let color = bitmap.colorAt(x: point.0, y: point.1)?.usingColorSpace(.deviceRGB) else { continue }
                red += color.redComponent
                green += color.greenComponent
                blue += color.blueComponent
                count += 1
            }
        }
        guard count > 0 else { return nil }
        let average = NSColor(
            calibratedRed: red / count,
            green: green / count,
            blue: blue / count,
            alpha: 1
        )
        let nearBlack = NSColor(calibratedRed: 0.025, green: 0.03, blue: 0.034, alpha: 1)
        return average.blended(withFraction: 0.82, of: nearBlack) ?? nearBlack
    }
}

private struct ComicImagePreview: View {
    let pages: [EpubImagePreviewPage]
    let readingDirection: EpubReadingDirection
    @ObservedObject var gestureRouter: PreviewGestureRouter
    let isChromeVisible: Bool
    let savePageIndex: (Int) -> Void
    @AppStorage("MobiVerseComicReadingMode") private var readingModeRawValue = ComicReadingMode.single.rawValue
    @State private var pageIndex: Int
    @State private var visibleUnitID: Int?
    @State private var continuousVisiblePageID: Int?
    @State private var zoom = 1.0
    @State private var canvasColor = Color(red: 0.045, green: 0.055, blue: 0.06)

    init(
        pages: [EpubImagePreviewPage],
        readingDirection: EpubReadingDirection,
        gestureRouter: PreviewGestureRouter,
        initialPageIndex: Int,
        isChromeVisible: Bool,
        savePageIndex: @escaping (Int) -> Void
    ) {
        let restoredPageIndex = min(max(initialPageIndex, 0), max(pages.count - 1, 0))
        self.pages = pages
        self.readingDirection = readingDirection
        self.gestureRouter = gestureRouter
        self.isChromeVisible = isChromeVisible
        self.savePageIndex = savePageIndex
        _pageIndex = State(initialValue: restoredPageIndex)
        _visibleUnitID = State(initialValue: restoredPageIndex)
        _continuousVisiblePageID = State(initialValue: restoredPageIndex)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                canvasBackground

                if readingMode == .continuous {
                    continuousReader(in: proxy.size)
                        .transition(.opacity)
                } else {
                    pagedReader(in: proxy.size)
                        .transition(.opacity)
                }

                if isChromeVisible {
                    readerControls
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            synchronizeVisiblePosition()
            configureGestureRouter()
        }
        .onDisappear {
            savePageIndex(pageIndex)
            gestureRouter.resetHandlers()
        }
        .onChange(of: pageIndex) { _, newPageIndex in
            savePageIndex(newPageIndex)
            configureGestureRouter()
        }
        .onChange(of: pages.count) { _, _ in
            configureGestureRouter()
        }
        .onChange(of: readingModeRawValue) { _, _ in
            zoom = 1
            synchronizeVisiblePosition()
            configureGestureRouter()
        }
        .task(id: pageIndex) {
            await preparePageContext()
        }
    }

    private var readingMode: ComicReadingMode {
        ComicReadingMode(rawValue: readingModeRawValue) ?? .single
    }

    private var pageUnits: [ComicPageUnit] {
        guard readingMode == .spread, !pages.isEmpty else {
            return pages.indices.map { ComicPageUnit(id: $0, pageIndices: [$0]) }
        }

        var units = [ComicPageUnit(id: 0, pageIndices: [0])]
        var index = 1
        while index < pages.count {
            let end = min(index + 2, pages.count)
            units.append(ComicPageUnit(id: index, pageIndices: Array(index..<end)))
            index = end
        }
        return units
    }

    private var currentUnitIndex: Int {
        pageUnits.firstIndex(where: { $0.pageIndices.contains(pageIndex) }) ?? 0
    }

    private var canMoveBackward: Bool {
        readingMode == .continuous ? pageIndex > 0 : currentUnitIndex > 0
    }

    private var canMoveForward: Bool {
        readingMode == .continuous
            ? pageIndex < pages.count - 1
            : currentUnitIndex < pageUnits.count - 1
    }

    private var pageCounter: String {
        guard readingMode == .spread, pageUnits.indices.contains(currentUnitIndex) else {
            return "\(pageIndex + 1) / \(pages.count)"
        }
        let indices = pageUnits[currentUnitIndex].pageIndices
        guard let first = indices.first, let last = indices.last, first != last else {
            return "\(pageIndex + 1) / \(pages.count)"
        }
        return "\(first + 1)–\(last + 1) / \(pages.count)"
    }

    private var canvasBackground: some View {
        LinearGradient(
            colors: [canvasColor.opacity(0.92), Color.black.opacity(0.96), canvasColor.opacity(0.72)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(Color.black.opacity(0.16))
        .ignoresSafeArea()
    }

    private func pagedReader(in size: CGSize) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(pageUnits) { unit in
                        pageUnitCanvas(unit, in: size)
                            .frame(width: size.width, height: size.height)
                            .id(unit.id)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0.84)
                                    .scaleEffect(phase.isIdentity ? 1 : 0.972)
                                    .offset(x: phase.isIdentity ? 0 : phase.value * 18)
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .environment(\.layoutDirection, readingDirection == .rightToLeft ? .rightToLeft : .leftToRight)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visibleUnitID)
            .onAppear {
                recenterCurrentUnit(with: scrollProxy, animated: false)
            }
            .onChange(of: visibleUnitID) { _, newValue in
                guard
                    let newValue,
                    let unit = pageUnits.first(where: { $0.id == newValue }),
                    let logicalPage = unit.pageIndices.first
                else { return }
                pageIndex = logicalPage
            }
            .onChange(of: size) { _, _ in
                recenterCurrentUnit(with: scrollProxy, animated: false)
            }
            .onChange(of: zoom) { _, _ in
                recenterCurrentUnit(with: scrollProxy, animated: false)
            }
        }
    }

    private func continuousReader(in size: CGSize) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 18) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        let pageSize = continuousPageSize(for: page, in: size)
                        EpubImagePage(page: page)
                            .frame(width: pageSize.width, height: pageSize.height)
                            .background(Color.white)
                            .shadow(color: .black.opacity(0.30), radius: 16, y: 8)
                            .id(index)
                            .accessibilityLabel(page.title)
                    }
                }
                .scrollTargetLayout()
                .padding(.top, 74)
                .padding(.bottom, 90)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollPosition(id: $continuousVisiblePageID, anchor: .top)
            .onAppear {
                continuousVisiblePageID = pageIndex
                scrollProxy.scrollTo(pageIndex, anchor: .top)
            }
            .onChange(of: continuousVisiblePageID) { _, newValue in
                guard let newValue else { return }
                pageIndex = min(max(newValue, 0), max(pages.count - 1, 0))
            }
        }
    }

    private var readerControls: some View {
        HStack(spacing: 9) {
            if readingDirection == .rightToLeft {
                navigationButton(title: "Next", icon: "chevron.left", enabled: canMoveForward, action: moveForward)
            } else {
                navigationButton(title: "Previous", icon: "chevron.left", enabled: canMoveBackward, action: moveBackward)
            }

            Slider(
                value: Binding(
                    get: { Double(pageIndex) },
                    set: { jump(to: Int($0.rounded())) }
                ),
                in: 0...Double(max(pages.count - 1, 0))
            )
            .tint(MobiPalette.sage)
            .frame(minWidth: 150, maxWidth: 390)
            .disabled(pages.count <= 1)

            Text(pageCounter)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(MobiPalette.ink.opacity(0.68))
                .frame(width: 92)

            if readingDirection == .rightToLeft {
                navigationButton(title: "Previous", icon: "chevron.right", enabled: canMoveBackward, action: moveBackward)
            } else {
                navigationButton(title: "Next", icon: "chevron.right", enabled: canMoveForward, action: moveForward)
            }

            Divider().frame(height: 22)

            Menu {
                ForEach(ComicReadingMode.allCases) { mode in
                    Button {
                        readingModeRawValue = mode.rawValue
                    } label: {
                        Label(mode.title, systemImage: readingMode == mode ? "checkmark" : mode.icon)
                    }
                }
            } label: {
                Image(systemName: readingMode.icon)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .help("Reading mode")
            .accessibilityLabel("Reading mode")

            controlButton(title: "Zoom out", icon: "minus.magnifyingglass") { zoomBy(-0.1) }
            Button("Fit") { zoom = 1 }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MobiPalette.ink.opacity(0.72))
                .frame(height: 28)
            controlButton(title: "Zoom in", icon: "plus.magnifyingglass") { zoomBy(0.1) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private func navigationButton(
        title: String,
        icon: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 30, height: 30)
                .background(MobiPalette.ink.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(MobiPalette.ink.opacity(enabled ? 0.74 : 0.20))
        .disabled(!enabled)
        .help(L10n.string(title))
        .accessibilityLabel(L10n.string(title))
    }

    private func controlButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(MobiPalette.ink.opacity(0.72))
        .help(L10n.string(title))
        .accessibilityLabel(L10n.string(title))
    }

    private func pageUnitCanvas(_ unit: ComicPageUnit, in containerSize: CGSize) -> some View {
        let logicalIndices = unit.pageIndices
        let displayedIndices: [Int] = readingDirection == .rightToLeft
            ? Array(logicalIndices.reversed())
            : logicalIndices
        let pageArea = CGSize(
            width: max(containerSize.width - 70, 1),
            height: max(containerSize.height - 42, 1)
        )
        let availablePageWidth = max((pageArea.width - CGFloat(max(logicalIndices.count - 1, 0)) * 3) / CGFloat(max(logicalIndices.count, 1)), 1)

        return HStack(spacing: 3) {
            ForEach(Array(displayedIndices), id: \.self) { index in
                let page = pages[index]
                let fitted = fittedPageSize(
                    for: page,
                    in: CGSize(width: availablePageWidth, height: pageArea.height)
                )
                EpubImagePage(page: page)
                    .frame(width: fitted.width * zoom, height: fitted.height * zoom)
                    .background(Color.white)
                    .shadow(color: .black.opacity(0.38), radius: 18, y: 8)
                    .accessibilityLabel(page.title)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(width: containerSize.width, height: containerSize.height, alignment: .center)
        .clipped()
    }

    private func fittedPageSize(for page: EpubImagePreviewPage, in containerSize: CGSize) -> CGSize {
        let pageSize = CGSize(width: max(1, page.width), height: max(1, page.height))
        let scale = min(containerSize.width / pageSize.width, containerSize.height / pageSize.height)
        return CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
    }

    private func continuousPageSize(for page: EpubImagePreviewPage, in containerSize: CGSize) -> CGSize {
        let width = min(max(containerSize.width - 96, 320), 920) * zoom
        let aspect = CGFloat(max(page.height, 1)) / CGFloat(max(page.width, 1))
        return CGSize(width: width, height: width * aspect)
    }

    private func moveBackward() {
        guard canMoveBackward else { return }
        if readingMode == .continuous {
            jump(to: pageIndex - 1)
        } else {
            let target = pageUnits[currentUnitIndex - 1]
            show(unit: target)
        }
    }

    private func moveForward() {
        guard canMoveForward else { return }
        if readingMode == .continuous {
            jump(to: pageIndex + 1)
        } else {
            let target = pageUnits[currentUnitIndex + 1]
            show(unit: target)
        }
    }

    private func jump(to requestedPage: Int) {
        let targetPage = min(max(requestedPage, 0), max(pages.count - 1, 0))
        pageIndex = targetPage
        withAnimation(.snappy(duration: 0.26)) {
            if readingMode == .continuous {
                continuousVisiblePageID = targetPage
            } else if let unit = pageUnits.first(where: { $0.pageIndices.contains(targetPage) }) {
                visibleUnitID = unit.id
            }
        }
    }

    private func show(unit: ComicPageUnit) {
        guard let firstPage = unit.pageIndices.first else { return }
        pageIndex = firstPage
        withAnimation(.snappy(duration: 0.26)) {
            visibleUnitID = unit.id
        }
    }

    private func zoomBy(_ delta: Double) {
        zoom = min(2.5, max(0.6, zoom + delta))
    }

    private func synchronizeVisiblePosition() {
        DispatchQueue.main.async {
            if readingMode == .continuous {
                continuousVisiblePageID = pageIndex
            } else if let unit = pageUnits.first(where: { $0.pageIndices.contains(pageIndex) }) {
                visibleUnitID = unit.id
            }
        }
    }

    private func recenterCurrentUnit(with scrollProxy: ScrollViewProxy, animated: Bool) {
        guard let unit = pageUnits.first(where: { $0.pageIndices.contains(pageIndex) }) else { return }
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.disablesAnimations = !animated
            withTransaction(transaction) {
                visibleUnitID = unit.id
                scrollProxy.scrollTo(unit.id, anchor: .center)
            }
        }
    }

    private func configureGestureRouter() {
        let logicalBackward = canMoveBackward
        let logicalForward = canMoveForward
        gestureRouter.handleSwipeChanged = nil
        gestureRouter.handleSwipeEnded = nil
        if readingMode == .continuous {
            gestureRouter.zoomBy = nil
        } else {
            gestureRouter.zoomBy = { delta in
                zoomBy(delta)
            }
        }

        if readingDirection == .rightToLeft {
            gestureRouter.canMoveBackward = logicalForward
            gestureRouter.canMoveForward = logicalBackward
            gestureRouter.moveBackward = moveForward
            gestureRouter.moveForward = moveBackward
        } else {
            gestureRouter.canMoveBackward = logicalBackward
            gestureRouter.canMoveForward = logicalForward
            gestureRouter.moveBackward = moveBackward
            gestureRouter.moveForward = moveForward
        }
    }

    private func preparePageContext() async {
        guard pages.indices.contains(pageIndex) else { return }
        let lower = max(pageIndex - 2, 0)
        let upper = min(pageIndex + 3, pages.count - 1)
        await EpubPreviewImageCache.shared.prefetch((lower...upper).map { pages[$0].imageURL })
        guard !Task.isCancelled else { return }
        let newColor = await EpubPreviewImageCache.shared.canvasColor(for: pages[pageIndex].imageURL)
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.45)) {
            canvasColor = newColor
        }
    }
}

private struct EpubImagePage: View {
    let page: EpubImagePreviewPage
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(CGSize(width: page.width, height: page.height), contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
        }
        .task(id: page.id) {
            image = await EpubPreviewImageCache.shared.image(for: page.imageURL)
        }
    }
}

private enum TextReaderTheme: String, CaseIterable, Identifiable {
    case paper
    case sepia
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: L10n.string("Paper")
        case .sepia: L10n.string("Sepia")
        case .night: L10n.string("Night")
        }
    }

    var pageColor: Color {
        switch self {
        case .paper: Color(red: 0.985, green: 0.978, blue: 0.95)
        case .sepia: Color(red: 0.94, green: 0.87, blue: 0.72)
        case .night: Color(red: 0.105, green: 0.135, blue: 0.14)
        }
    }

    var canvasColor: Color {
        switch self {
        case .paper: Color(red: 0.89, green: 0.875, blue: 0.82)
        case .sepia: Color(red: 0.76, green: 0.68, blue: 0.54)
        case .night: Color(red: 0.045, green: 0.06, blue: 0.065)
        }
    }

    var primaryColor: Color {
        self == .night ? Color(red: 0.88, green: 0.87, blue: 0.81) : MobiPalette.ink
    }

    var cssPageColor: String {
        switch self {
        case .paper: "#fbf8ef"
        case .sepia: "#f0dfb8"
        case .night: "#1b2324"
        }
    }

    var cssInkColor: String {
        switch self {
        case .paper: "#223034"
        case .sepia: "#3d3024"
        case .night: "#e1dfd2"
        }
    }

    var cssMutedColor: String {
        switch self {
        case .paper: "#677174"
        case .sepia: "#796a57"
        case .night: "#aab2ae"
        }
    }

    var cssAccentColor: String {
        switch self {
        case .paper: "#8f4935"
        case .sepia: "#7a4930"
        case .night: "#d78a70"
        }
    }
}

private struct TextReaderAppearance: Equatable {
    let theme: TextReaderTheme
    let fontScale: Double
    let lineHeight: Double
}

private struct TextEpubPreview: View {
    let spineURLs: [URL]
    let readAccessURL: URL
    let readingDirection: EpubReadingDirection
    @ObservedObject var gestureRouter: PreviewGestureRouter
    let savePosition: (PreviewReadingPosition) -> Void
    let isChromeVisible: Bool
    @State private var sectionIndex: Int
    @State private var pageIndex: Int
    @State private var pageCount = 1
    @State private var shouldOpenLastPage = false
    @State private var showsAppearance = false
    @AppStorage("MobiVerseTextReaderTheme") private var themeRawValue = TextReaderTheme.paper.rawValue
    @AppStorage("MobiVerseTextReaderFontScale") private var fontScale = 1.0
    @AppStorage("MobiVerseTextReaderLineHeight") private var lineHeight = 1.64

    init(
        spineURLs: [URL],
        readAccessURL: URL,
        readingDirection: EpubReadingDirection,
        gestureRouter: PreviewGestureRouter,
        initialPosition: PreviewReadingPosition,
        isChromeVisible: Bool,
        savePosition: @escaping (PreviewReadingPosition) -> Void
    ) {
        self.spineURLs = spineURLs
        self.readAccessURL = readAccessURL
        self.readingDirection = readingDirection
        self.gestureRouter = gestureRouter
        self.isChromeVisible = isChromeVisible
        self.savePosition = savePosition
        _sectionIndex = State(
            initialValue: min(max(initialPosition.sectionIndex, 0), max(spineURLs.count - 1, 0))
        )
        _pageIndex = State(initialValue: max(initialPosition.pageIndex, 0))
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                ZStack {
                    theme.canvasColor

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(theme.pageColor)
                        .shadow(color: .black.opacity(theme == .night ? 0.28 : 0.13), radius: 22, y: 8)

                    EpubWebPreview(
                        startURL: spineURLs[sectionIndex],
                        readAccessURL: readAccessURL,
                        pageIndex: pageIndex,
                        viewportSize: CGSize(width: max(proxy.size.width - 52, 1), height: max(proxy.size.height - 50, 1)),
                        appearance: appearance,
                        onPageCountChanged: updatePageCount
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if isChromeVisible {
                        readerPositionBadge
                            .padding(.horizontal, 13)
                            .padding(.top, 62)
                            .padding(.bottom, 13)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 25)
                .background(theme.canvasColor)
            }

            if isChromeVisible {
                readerControls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear(perform: configureGestureRouter)
        .onDisappear {
            saveCurrentPosition()
            gestureRouter.resetHandlers()
        }
        .onChange(of: sectionIndex) { _, _ in
            saveCurrentPosition()
            configureGestureRouter()
        }
        .onChange(of: pageIndex) { _, _ in
            saveCurrentPosition()
            configureGestureRouter()
        }
        .onChange(of: pageCount) { _, _ in
            configureGestureRouter()
        }
    }

    private var theme: TextReaderTheme {
        TextReaderTheme(rawValue: themeRawValue) ?? .paper
    }

    private var appearance: TextReaderAppearance {
        TextReaderAppearance(theme: theme, fontScale: fontScale, lineHeight: lineHeight)
    }

    private var readerPositionBadge: some View {
        VStack {
            HStack {
                Text(L10n.format("SECTION %lld OF %lld", sectionIndex + 1, spineURLs.count))
                    .font(.caption2.weight(.bold))
                    .tracking(1.15)
                Spacer()
                Text(L10n.format("PAGE %lld OF %lld", pageIndex + 1, pageCount))
                    .font(.caption2.monospacedDigit().weight(.semibold))
            }
            .foregroundStyle(theme.primaryColor.opacity(0.46))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var readerControls: some View {
        HStack(spacing: 14) {
            if readingDirection == .rightToLeft {
                readerNavigationButton(
                    title: "Next page",
                    icon: "chevron.left",
                    enabled: canMoveForward,
                    action: moveForward
                )
            } else {
                readerNavigationButton(
                    title: "Previous page",
                    icon: "chevron.left",
                    enabled: canMoveBackward,
                    action: moveBackward
                )
            }

            VStack(spacing: 5) {
                ProgressView(value: overallProgress)
                    .progressViewStyle(.linear)
                    .tint(MobiPalette.sage)
                HStack {
                    Text(L10n.format("Section %lld · Page %lld", sectionIndex + 1, pageIndex + 1))
                    Spacer()
                    Text(overallProgress.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(MobiPalette.ink.opacity(0.55))
            }
            .frame(maxWidth: 420)

            if readingDirection == .rightToLeft {
                readerNavigationButton(
                    title: "Previous page",
                    icon: "chevron.right",
                    enabled: canMoveBackward,
                    action: moveBackward
                )
            } else {
                readerNavigationButton(
                    title: "Next page",
                    icon: "chevron.right",
                    enabled: canMoveForward,
                    action: moveForward
                )
            }

            Divider().frame(height: 28)

            Button {
                showsAppearance.toggle()
            } label: {
                Label("Reading appearance", systemImage: "textformat")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(MobiPalette.cream.opacity(0.66), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(MobiPalette.ink.opacity(0.78))
            .popover(isPresented: $showsAppearance, arrowEdge: .bottom) {
                appearancePanel
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 7)
        .padding(.horizontal, 18)
        .padding(.bottom, 15)
    }

    private func readerNavigationButton(
        title: String,
        icon: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 34, height: 34)
                .background(MobiPalette.ink.opacity(0.055), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(MobiPalette.ink.opacity(enabled ? 0.76 : 0.22))
        .disabled(!enabled)
        .help(L10n.string(title))
        .accessibilityLabel(L10n.string(title))
    }

    private var appearancePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Reading appearance")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                Text("Choose a page that feels comfortable for longer sessions.")
                    .font(.caption)
                    .foregroundStyle(MobiPalette.ink.opacity(0.55))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("PAGE THEME")
                    .font(.caption2.weight(.bold)).tracking(1)
                    .foregroundStyle(MobiPalette.ink.opacity(0.48))
                HStack(spacing: 9) {
                    ForEach(TextReaderTheme.allCases) { option in
                        Button {
                            themeRawValue = option.rawValue
                        } label: {
                            VStack(spacing: 7) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(option.pageColor)
                                    .frame(height: 42)
                                    .overlay {
                                        VStack(spacing: 4) {
                                            Capsule().fill(option.primaryColor.opacity(0.72)).frame(width: 34, height: 2)
                                            Capsule().fill(option.primaryColor.opacity(0.42)).frame(width: 27, height: 2)
                                        }
                                    }
                                Text(option.title).font(.caption.weight(.medium))
                            }
                            .padding(7)
                            .frame(width: 82)
                            .background(
                                theme == option ? MobiPalette.sage.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(theme == option ? MobiPalette.sage.opacity(0.55) : MobiPalette.ink.opacity(0.08), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            appearanceSlider(
                title: "Text size",
                leading: "A",
                trailing: "A",
                value: $fontScale,
                range: 0.86...1.32,
                trailingScale: 1.3
            )

            appearanceSlider(
                title: "Line spacing",
                leading: "Tight",
                trailing: "Airy",
                value: $lineHeight,
                range: 1.45...1.85
            )

            Button("Restore defaults") {
                themeRawValue = TextReaderTheme.paper.rawValue
                fontScale = 1.0
                lineHeight = 1.64
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(MobiPalette.terracotta)
        }
        .foregroundStyle(MobiPalette.ink)
        .padding(20)
        .frame(width: 310)
        .background(MobiPalette.paper)
    }

    private func appearanceSlider(
        title: String,
        leading: String,
        trailing: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        trailingScale: Double = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.string(title).uppercased())
                .font(.caption2.weight(.bold)).tracking(1)
                .foregroundStyle(MobiPalette.ink.opacity(0.48))
            HStack(spacing: 10) {
                Text(L10n.string(leading)).font(.caption)
                Slider(value: value, in: range)
                    .tint(MobiPalette.sage)
                Text(L10n.string(trailing)).font(.caption).scaleEffect(trailingScale)
            }
        }
    }

    private var overallProgress: Double {
        let sectionProgress = Double(pageIndex + 1) / Double(max(pageCount, 1))
        return min(max((Double(sectionIndex) + sectionProgress) / Double(max(spineURLs.count, 1)), 0), 1)
    }

    private func saveCurrentPosition() {
        savePosition(
            PreviewReadingPosition(sectionIndex: sectionIndex, pageIndex: pageIndex)
        )
    }

    private func moveBackward() {
        if pageIndex > 0 {
            pageIndex -= 1
        } else if sectionIndex > 0 {
            shouldOpenLastPage = true
            pageCount = 1
            pageIndex = 0
            sectionIndex -= 1
        }
    }

    private func moveForward() {
        if pageIndex < pageCount - 1 {
            pageIndex += 1
        } else if sectionIndex < spineURLs.count - 1 {
            shouldOpenLastPage = false
            pageCount = 1
            pageIndex = 0
            sectionIndex += 1
        }
    }

    private var canMoveBackward: Bool {
        pageIndex > 0 || sectionIndex > 0
    }

    private var canMoveForward: Bool {
        pageIndex < pageCount - 1 || sectionIndex < spineURLs.count - 1
    }

    private func updatePageCount(_ newPageCount: Int) {
        pageCount = max(newPageCount, 1)
        if shouldOpenLastPage {
            pageIndex = pageCount - 1
            shouldOpenLastPage = false
        } else {
            pageIndex = min(pageIndex, pageCount - 1)
        }
    }

    private func configureGestureRouter() {
        gestureRouter.handleSwipeChanged = nil
        gestureRouter.handleSwipeEnded = nil
        gestureRouter.zoomBy = nil
        if readingDirection == .rightToLeft {
            gestureRouter.canMoveBackward = canMoveForward
            gestureRouter.canMoveForward = canMoveBackward
            gestureRouter.moveBackward = moveForward
            gestureRouter.moveForward = moveBackward
        } else {
            gestureRouter.canMoveBackward = canMoveBackward
            gestureRouter.canMoveForward = canMoveForward
            gestureRouter.moveBackward = moveBackward
            gestureRouter.moveForward = moveForward
        }
    }
}

private struct EpubWebPreview: NSViewRepresentable {
    let startURL: URL
    let readAccessURL: URL
    let pageIndex: Int
    let viewportSize: CGSize
    let appearance: TextReaderAppearance
    let onPageCountChanged: (Int) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.prepare(view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.update(
            startURL: startURL,
            readAccessURL: readAccessURL,
            pageIndex: pageIndex,
            viewportSize: viewportSize,
            appearance: appearance,
            onPageCountChanged: onPageCountChanged
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private weak var webView: WKWebView?
        private var isNetworkBlockingReady = false
        private var pendingLoad: (startURL: URL, readAccessURL: URL)?
        private var allowedRootURL: URL?
        private var loadedURL: URL?
        private var requestedPageIndex = 0
        private var viewportSize = CGSize.zero
        private var appearance = TextReaderAppearance(theme: .paper, fontScale: 1, lineHeight: 1.64)
        private var onPageCountChanged: ((Int) -> Void)?

        func prepare(_ webView: WKWebView) {
            self.webView = webView
            let rules = #"[{"trigger":{"url-filter":"^https?://.*"},"action":{"type":"block"}}]"#
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "MobiVerseBlockEPUBNetworkAccess",
                encodedContentRuleList: rules
            ) { [weak self, weak webView] ruleList, _ in
                guard let self, let webView, let ruleList else { return }
                webView.configuration.userContentController.add(ruleList)
                isNetworkBlockingReady = true
                performPendingLoadIfPossible()
            }
        }

        func update(
            startURL: URL,
            readAccessURL: URL,
            pageIndex: Int,
            viewportSize: CGSize,
            appearance: TextReaderAppearance,
            onPageCountChanged: @escaping (Int) -> Void
        ) {
            guard EpubPathSecurity.contains(startURL, in: readAccessURL) else {
                webView?.stopLoading()
                return
            }
            let viewportChanged = abs(self.viewportSize.width - viewportSize.width) > 1
                || abs(self.viewportSize.height - viewportSize.height) > 1
            let appearanceChanged = self.appearance != appearance
            allowedRootURL = readAccessURL
            requestedPageIndex = max(pageIndex, 0)
            self.viewportSize = viewportSize
            self.appearance = appearance
            self.onPageCountChanged = onPageCountChanged
            if loadedURL != startURL {
                loadedURL = startURL
                pendingLoad = (startURL, readAccessURL)
            } else if viewportChanged || appearanceChanged {
                installPagination(in: webView)
            } else {
                showRequestedPage(in: webView)
            }
            performPendingLoadIfPossible()
        }

        private func performPendingLoadIfPossible() {
            guard
                isNetworkBlockingReady,
                let webView,
                let pendingLoad,
                loadedURL == pendingLoad.startURL
            else {
                return
            }
            self.pendingLoad = nil
            webView.loadFileURL(pendingLoad.startURL, allowingReadAccessTo: pendingLoad.readAccessURL)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            installPagination(in: webView)
        }

        private func installPagination(in webView: WKWebView?) {
            guard let webView else { return }
            let theme = appearance.theme
            let fontSize = 18 * min(max(appearance.fontScale, 0.86), 1.32)
            let lineHeight = min(max(appearance.lineHeight, 1.45), 1.85)
            let script = #"""
            (() => {
              const styleID = 'mobiverse-pagination-style';
              let style = document.getElementById(styleID);
              if (!style) {
                style = document.createElement('style');
                style.id = styleID;
                document.head.appendChild(style);
              }
              style.textContent = `
                html, body {
                  width: 100% !important;
                  height: 100% !important;
                  min-height: 100% !important;
                  margin: 0 !important;
                  padding: 0 !important;
                  overflow: hidden !important;
                  background: \#(theme.cssPageColor) !important;
                  color: \#(theme.cssInkColor) !important;
                }
                #mobiverse-reader-pages {
                  box-sizing: border-box !important;
                  width: 100vw !important;
                  height: 100vh !important;
                  padding: clamp(28px, 5vh, 56px) var(--mobiverse-page-side) !important;
                  overflow: visible !important;
                  column-width: calc(100vw - (2 * var(--mobiverse-page-side))) !important;
                  column-gap: calc(2 * var(--mobiverse-page-side)) !important;
                  column-fill: auto !important;
                  transform: translateX(calc(-1 * var(--mobiverse-page-index) * 100vw));
                  transition: transform 180ms ease-out;
                  color: \#(theme.cssInkColor) !important;
                  font-family: "Iowan Old Style", "Palatino Linotype", Palatino, Georgia, serif !important;
                  font-size: \#(fontSize)px !important;
                  font-weight: 400 !important;
                  line-height: \#(lineHeight) !important;
                  letter-spacing: 0.008em !important;
                  text-rendering: optimizeLegibility;
                  -webkit-font-smoothing: antialiased;
                  font-kerning: normal;
                  hyphens: auto;
                }
                #mobiverse-reader-pages p,
                #mobiverse-reader-pages li,
                #mobiverse-reader-pages blockquote {
                  color: \#(theme.cssInkColor) !important;
                  font-family: inherit !important;
                  font-size: 1em !important;
                  line-height: inherit !important;
                  orphans: 3;
                  widows: 3;
                }
                #mobiverse-reader-pages p {
                  margin-top: 0 !important;
                  margin-bottom: 0 !important;
                  text-indent: 1.35em !important;
                }
                #mobiverse-reader-pages h1 + p,
                #mobiverse-reader-pages h2 + p,
                #mobiverse-reader-pages h3 + p,
                #mobiverse-reader-pages .COTX,
                #mobiverse-reader-pages .first,
                #mobiverse-reader-pages .noindent,
                #mobiverse-reader-pages p:first-child {
                  text-indent: 0 !important;
                }
                #mobiverse-reader-pages h1,
                #mobiverse-reader-pages h2,
                #mobiverse-reader-pages h3,
                #mobiverse-reader-pages h4 {
                  color: \#(theme.cssInkColor) !important;
                  font-family: "Iowan Old Style", Palatino, Georgia, serif !important;
                  font-weight: 600 !important;
                  text-wrap: balance;
                  break-after: avoid;
                }
                #mobiverse-reader-pages h1.chapter-number {
                  color: \#(theme.cssAccentColor) !important;
                  font-family: -apple-system, BlinkMacSystemFont, sans-serif !important;
                  font-size: 0.78em !important;
                  font-weight: 700 !important;
                  letter-spacing: 0.18em !important;
                  margin-top: 7vh !important;
                  margin-bottom: 0.7em !important;
                }
                #mobiverse-reader-pages h1.chapter-title {
                  font-size: 1.82em !important;
                  letter-spacing: 0.045em !important;
                  line-height: 1.16 !important;
                  margin-top: 0 !important;
                  margin-bottom: 1.65em !important;
                }
                #mobiverse-reader-pages blockquote {
                  color: \#(theme.cssMutedColor) !important;
                  border-left: 2px solid \#(theme.cssAccentColor) !important;
                  margin: 1.1em 1.5em !important;
                  padding-left: 1em !important;
                }
                #mobiverse-reader-pages a {
                  color: \#(theme.cssAccentColor) !important;
                  text-decoration-thickness: 0.06em;
                  text-underline-offset: 0.15em;
                }
                #mobiverse-reader-pages [role="doc-pagebreak"] {
                  display: none !important;
                }
                #mobiverse-reader-pages hr {
                  width: 24% !important;
                  margin: 1.5em auto !important;
                  border: 0 !important;
                  border-top: 1px solid \#(theme.cssMutedColor) !important;
                  opacity: 0.45;
                }
                #mobiverse-reader-pages img,
                #mobiverse-reader-pages svg {
                  display: block !important;
                  margin-left: auto !important;
                  margin-right: auto !important;
                  max-width: calc(100vw - (2 * var(--mobiverse-page-side))) !important;
                  max-height: calc(100vh - clamp(56px, 10vh, 112px)) !important;
                  object-fit: contain !important;
                  break-inside: avoid !important;
                }
                #mobiverse-reader-pages figure,
                #mobiverse-reader-pages .media-rw,
                #mobiverse-reader-pages .image-rw,
                #mobiverse-reader-pages p.img {
                  text-align: center !important;
                  margin-left: auto !important;
                  margin-right: auto !important;
                  break-inside: avoid !important;
                }
                #mobiverse-reader-pages pre,
                #mobiverse-reader-pages table {
                  max-width: 100% !important;
                  overflow-wrap: anywhere !important;
                }
              `;
              let pages = document.getElementById('mobiverse-reader-pages');
              if (!pages) {
                pages = document.createElement('div');
                pages.id = 'mobiverse-reader-pages';
                const nodes = Array.from(document.body.childNodes).filter(node => node !== style);
                nodes.forEach(node => pages.appendChild(node));
                document.body.appendChild(pages);
              }
              const pageWidth = Math.min(760, Math.max(360, window.innerWidth - 96));
              const side = Math.max(48, (window.innerWidth - pageWidth) / 2);
              pages.style.setProperty('--mobiverse-page-side', `${side}px`);
              pages.style.setProperty('--mobiverse-page-index', '0');
              const count = Math.max(1, Math.ceil((pages.scrollWidth - 1) / Math.max(window.innerWidth, 1)));
              window.__mobiversePageCount = count;
              window.__mobiverseSetPage = index => {
                const safeIndex = Math.max(0, Math.min(Number(index) || 0, count - 1));
                pages.style.setProperty('--mobiverse-page-index', String(safeIndex));
                return safeIndex;
              };
              return count;
            })();
            """#
            webView.evaluateJavaScript(script) { [weak self, weak webView] result, _ in
                guard let self else { return }
                let count = max((result as? NSNumber)?.intValue ?? 1, 1)
                DispatchQueue.main.async {
                    self.onPageCountChanged?(count)
                    self.showRequestedPage(in: webView)
                }
            }
        }

        private func showRequestedPage(in webView: WKWebView?) {
            guard let webView else { return }
            webView.evaluateJavaScript("window.__mobiverseSetPage?.(\(requestedPageIndex));")
        }

        @MainActor
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard
                let targetURL = navigationAction.request.url,
                let allowedRootURL,
                EpubPathSecurity.contains(targetURL, in: allowedRootURL)
            else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct MissingFileBadge: View {
    var body: some View {
        Label("File missing", systemImage: "questionmark.folder.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.secondary.opacity(0.12), in: Capsule())
    }
}

private struct StatusBadge: View {
    let status: ConversionStatus

    var body: some View {
        Label(L10n.string(status.displayName), systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var systemImage: String {
        switch status {
        case .queued: "clock"
        case .checkingTools: "magnifyingglass"
        case .converting: "arrow.triangle.2.circlepath"
        case .validating: "checklist"
        case .succeeded: "checkmark.circle.fill"
        case .succeededWithWarnings: "exclamationmark.triangle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .queued, .checkingTools, .converting, .validating: .blue
        case .succeeded: .green
        case .succeededWithWarnings: .orange
        case .failed: .red
        }
    }
}
