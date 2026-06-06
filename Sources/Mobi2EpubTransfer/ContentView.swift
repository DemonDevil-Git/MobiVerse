import Mobi2EpubTransferCore
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct ContentView: View {
    @StateObject private var viewModel = ConversionViewModel()
    @State private var isSidebarVisible = true
    @State private var isToolStatusPresented = false
    @State private var previewWindowController: EpubPreviewWindowController?
    @State private var previewError: PreviewError?

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                sidebar
                    .frame(width: 300)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                Divider()
            }

            mainContent
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
                .help(isSidebarVisible ? "Hide sidebar" : "Show sidebar")
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
                viewModel.addFiles(urls)
            }
        }
        .alert(item: $previewError) { error in
            Alert(
                title: Text("Preview unavailable"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("MobiVerse")
                    .font(.title2.weight(.semibold))
                Text("Convert MOBI, AZW, and AZW3 books into elegant EPUBs for comics and illustrated reading.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                viewModel.isImporterPresented = true
            } label: {
                Label("Choose books", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                viewModel.retryFailedTasks()
            } label: {
                Label("Retry failed", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(20)
    }

    private var toolchainDetailMessage: String {
        let calibreMessage = viewModel.toolchain.calibreSource == .bundled
            ? "Using the Calibre copy packaged inside this app."
            : "Using the Calibre installation found on this Mac."

        if viewModel.toolchain.epubCheckURL == nil {
            return "\(calibreMessage) EPUBCheck was not found, so validation reports will be marked as skipped."
        } else {
            return "\(calibreMessage) EPUBCheck is available. Converted EPUB files will be structurally validated."
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            dropZone
            taskList
        }
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "books.vertical")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Drop MOBI, AZW, or AZW3 files here")
                .font(.headline)
            Text("EPUB files are written beside the original book without overwriting existing files.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .background(.thinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                .foregroundStyle(.tertiary)
        )
        .padding(20)
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            loadDroppedFiles(from: providers)
            return true
        }
    }

    private var taskList: some View {
        List(viewModel.tasks) { task in
            TaskRow(
                task: task,
                isOutputMissing: viewModel.isOutputMissing(for: task),
                canDelete: viewModel.canDelete(task)
            ) {
                preview(task)
            } revealOutput: {
                viewModel.revealOutput(for: task)
            } openReport: {
                viewModel.openReport(for: task)
            } deleteHistory: {
                viewModel.deleteTask(task)
            }
        }
        .overlay {
            if viewModel.tasks.isEmpty {
                ContentUnavailableView(
                    "No conversion history",
                    systemImage: "book",
                    description: Text("Choose files or drag them into the window to begin.")
                )
            }
        }
    }

    private var allowedContentTypes: [UTType] {
        [
            UTType(filenameExtension: "mobi"),
            UTType(filenameExtension: "azw"),
            UTType(filenameExtension: "azw3")
        ].compactMap { $0 }
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
                    viewModel.addFiles([url])
                }
            }
        }
    }

    private func preview(_ task: ConversionTask) {
        guard let outputURL = task.outputURL else { return }
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
                    previewWindowController?.close()
                    let controller = EpubPreviewWindowController(book: book)
                    controller.onClose = {
                        previewWindowController = nil
                    }
                    previewWindowController = controller
                    controller.show()
                }
            } catch let error as EpubPreviewParserError {
                try? FileManager.default.removeItem(at: extractionDirectory)
                await MainActor.run {
                    previewError = PreviewError(message: error.message)
                }
            } catch {
                try? FileManager.default.removeItem(at: extractionDirectory)
                await MainActor.run {
                    previewError = PreviewError(message: error.localizedDescription)
                }
            }
        }
    }
}

private struct PreviewError: Identifiable {
    let id = UUID()
    let message: String
}

@MainActor
private final class EpubPreviewWindowState: ObservableObject {
    @Published var isFullScreen = false
}

@MainActor
private final class PreviewGestureRouter: ObservableObject {
    @Published var diagnosticText = "Input: waiting"
    var canMoveBackward = false
    var canMoveForward = false
    var handleSwipeChanged: ((Double) -> Void)?
    var handleSwipeEnded: ((Double) -> Void)?
    var zoomBy: ((Double) -> Void)?

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
        finishHorizontalSwipe()
    }

    func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .magnify:
            zoomBy?(Double(event.magnification) * 1.8)
            return nil
        case .swipe:
            handleSwipeEvent(event)
            return nil
        case .scrollWheel:
            return handleScrollWheelEvent(event) ? nil : event
        default:
            return event
        }
    }

    func handleScrollWheel(_ event: NSEvent) -> Bool {
        handleScrollWheelEvent(event)
    }

    func handleMagnify(_ event: NSEvent) {
        diagnosticText = String(format: "Input: magnify %.3f", Double(event.magnification))
        zoomBy?(Double(event.magnification) * 1.8)
    }

    func handleSwipe(_ event: NSEvent) {
        handleSwipeEvent(event)
    }

    private func handleScrollWheelEvent(_ event: NSEvent) -> Bool {
        guard handleSwipeChanged != nil, handleSwipeEnded != nil else {
            return false
        }
        guard isTrackingHorizontalSwipe || isHorizontalPageSwipe(event) else {
            return false
        }
        diagnosticText = String(
            format: "Input: scroll dx %.2f dy %.2f phase %@",
            Double(event.scrollingDeltaX),
            Double(event.scrollingDeltaY),
            phaseDescription(event.phase)
        )

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
        diagnosticText = String(format: "Input: swipe dx %.2f -> %.0f", Double(event.deltaX), syntheticDelta)
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
        diagnosticText = String(format: "Input: end %.2f", horizontalSwipeDelta)
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

    private func phaseDescription(_ phase: NSEvent.Phase) -> String {
        switch phase {
        case .began: "began"
        case .changed: "changed"
        case .ended: "ended"
        case .cancelled: "cancelled"
        case .mayBegin: "mayBegin"
        default: "none"
        }
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
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.minSize = NSSize(width: 780, height: 620)
        super.init(window: window)
        window.delegate = self
        window.contentView = PreviewHostingView(
            rootView: EpubPreviewView(
                book: book,
                windowState: windowState,
                gestureRouter: gestureRouter,
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
            ),
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
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify, .swipe]) { [weak self] event in
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
                        Text(canConvert ? toolchain.calibreSource.displayName : "Calibre missing")
                            .font(.headline)
                        Text(epubCheckSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(missingToolsMessage ?? detailMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button {
                        refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
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

private struct TaskRow: View {
    let task: ConversionTask
    let isOutputMissing: Bool
    let canDelete: Bool
    let preview: () -> Void
    let revealOutput: () -> Void
    let openReport: () -> Void
    let deleteHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.inputURL.deletingPathExtension().lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                    Text(task.inputURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let completedAt = task.completedAt {
                        Text("Completed \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if isOutputMissing {
                    MissingFileBadge()
                } else {
                    StatusBadge(status: task.status)
                }
            }

            ProgressView(value: task.progress)
                .progressViewStyle(.linear)
                .opacity(isOutputMissing ? 0.35 : 1)

            HStack {
                Text(isOutputMissing ? "Converted EPUB is no longer at the saved output path." : task.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer()

                Button {
                    preview()
                } label: {
                    Label("Preview", systemImage: "book.pages")
                }
                .disabled(!canPreview)

                Button {
                    revealOutput()
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .disabled(task.outputURL == nil || isOutputMissing)

                Button {
                    openReport()
                } label: {
                    Label("Report", systemImage: "doc.text")
                }
                .disabled(task.reportURL == nil)

                Button(role: .destructive) {
                    deleteHistory()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(!canDelete)
                .help(canDelete ? "Delete this history record" : "Active conversions cannot be deleted")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 8)
        .opacity(isOutputMissing ? 0.48 : 1)
    }

    private var canPreview: Bool {
        !isOutputMissing && (task.status == .succeeded || task.status == .succeededWithWarnings) && task.outputURL != nil
    }
}

private struct EpubPreviewView: View {
    let book: EpubPreviewBook
    @ObservedObject var windowState: EpubPreviewWindowState
    let gestureRouter: PreviewGestureRouter
    let toggleFullScreen: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(modeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    toggleFullScreen()
                } label: {
                    Label(fullScreenButtonLabel, systemImage: fullScreenButtonIcon)
                        .frame(width: 30, height: 26)
                }
                .buttonStyle(.bordered)
                .help(fullScreenButtonLabel)

                Button {
                    close()
                } label: {
                    Label("Close Preview", systemImage: "xmark")
                        .frame(width: 30, height: 26)
                }
                .buttonStyle(.bordered)
                .help("Close preview")
            }
            .labelStyle(.iconOnly)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            switch book.mode {
            case .imagePages(let pages):
                ComicImagePreview(pages: pages, gestureRouter: gestureRouter)
            case .web(let startURL):
                EpubWebPreview(startURL: startURL, readAccessURL: book.contentRootDirectory)
                    .onAppear {
                        gestureRouter.resetHandlers()
                    }
            }
        }
    }

    private var modeLabel: String {
        switch book.mode {
        case .imagePages(let pages):
            "\(pages.count) image pages"
        case .web:
            "Text EPUB preview"
        }
    }

    private var fullScreenButtonLabel: String {
        windowState.isFullScreen ? "Exit full screen" : "Enter full screen"
    }

    private var fullScreenButtonIcon: String {
        windowState.isFullScreen
            ? "arrow.down.right.and.arrow.up.left"
            : "arrow.up.left.and.arrow.down.right"
    }
}

private struct ComicImagePreview: View {
    let pages: [EpubImagePreviewPage]
    @ObservedObject var gestureRouter: PreviewGestureRouter
    @State private var pageIndex = 0
    @State private var visiblePageIndex: Int?
    @State private var zoom = 1.0

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ZStack {
                    Color.black
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                                pageCanvas(for: page, in: proxy.size)
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                                    .id(index)
                                    .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                        content
                                            .opacity(phase.isIdentity ? 1 : 0.92)
                                            .scaleEffect(phase.isIdentity ? 1 : 0.985)
                                    }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $visiblePageIndex)
                    .onAppear {
                        visiblePageIndex = pageIndex
                    }
                    .onChange(of: visiblePageIndex) { _, newValue in
                        guard let newValue else { return }
                        pageIndex = min(max(newValue, 0), max(pages.count - 1, 0))
                    }
                }
            }
            .onAppear(perform: configureGestureRouter)
            .onDisappear {
                gestureRouter.resetHandlers()
            }
            .onChange(of: pageIndex) { _, _ in
                configureGestureRouter()
            }
            .onChange(of: pages.count) { _, _ in
                configureGestureRouter()
            }

            HStack(spacing: 12) {
                Button {
                    moveBackward()
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .disabled(pageIndex == 0)

                Slider(
                    value: Binding(
                        get: { Double(pageIndex) },
                        set: { pageIndex = min(max(Int($0.rounded()), 0), max(pages.count - 1, 0)) }
                    ),
                    in: 0...Double(max(pages.count - 1, 0))
                )
                .disabled(pages.count <= 1)

                Text("\(pageIndex + 1) / \(pages.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 76)

                Button {
                    moveForward()
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .disabled(pageIndex >= pages.count - 1)

                Divider()
                    .frame(height: 18)

                Button {
                    zoomBy(-0.1)
                } label: {
                    Label("Zoom out", systemImage: "minus.magnifyingglass")
                }

                Button {
                    zoom = 1.0
                } label: {
                    Text("Fit")
                }

                Button {
                    zoomBy(0.1)
                } label: {
                    Label("Zoom in", systemImage: "plus.magnifyingglass")
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(12)
            .background(.bar)
        }
    }

    private func moveBackward() {
        guard pageIndex > 0 else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            visiblePageIndex = pageIndex - 1
        }
    }

    private func moveForward() {
        guard pageIndex < pages.count - 1 else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            visiblePageIndex = pageIndex + 1
        }
    }

    private func zoomBy(_ delta: Double) {
        zoom = min(3.0, max(0.5, zoom + delta))
    }

    private func configureGestureRouter() {
        gestureRouter.canMoveBackward = pageIndex > 0
        gestureRouter.canMoveForward = pageIndex < pages.count - 1
        gestureRouter.handleSwipeChanged = nil
        gestureRouter.handleSwipeEnded = nil
        gestureRouter.zoomBy = zoomBy
    }

    private func fittedPageSize(for page: EpubImagePreviewPage, in containerSize: CGSize) -> CGSize {
        let pageSize = CGSize(width: max(1, page.width), height: max(1, page.height))
        let scale = min(containerSize.width / pageSize.width, containerSize.height / pageSize.height)
        return CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
    }

    private func pageCanvas(for page: EpubImagePreviewPage, in containerSize: CGSize) -> some View {
        let fittedSize = fittedPageSize(for: page, in: containerSize)
        let scaledSize = CGSize(
            width: fittedSize.width * zoom,
            height: fittedSize.height * zoom
        )
        return ZStack {
            Color.black
            EpubImagePage(page: page)
                .frame(width: scaledSize.width, height: scaledSize.height)
        }
        .frame(width: containerSize.width, height: containerSize.height, alignment: .center)
        .clipped()
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
            }
        }
        .task(id: page.id) {
            image = NSImage(contentsOf: page.imageURL)
        }
    }
}

private struct EpubWebPreview: NSViewRepresentable {
    let startURL: URL
    let readAccessURL: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard view.url != startURL else { return }
        view.loadFileURL(startURL, allowingReadAccessTo: readAccessURL)
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
        Label(status.displayName, systemImage: systemImage)
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
