import Mobi2EpubTransferCore
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct ContentView: View {
    @StateObject private var viewModel = ConversionViewModel()
    @ObservedObject private var openBookRouter = OpenBookRouter.shared
    @State private var isSidebarVisible = true
    @State private var isToolStatusPresented = false
    @State private var previewWindowController: EpubPreviewWindowController?
    @State private var previewError: PreviewError?
    @State private var readingPreparation: ReadingPreparation?
    @State private var taskLayout = TaskLayout.grid

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                sidebar
                    .frame(width: 286)
                    .transition(.move(edge: .leading).combined(with: .opacity))
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
                openBooks(urls)
            }
        }
        .alert(item: $previewError) { error in
            Alert(
                title: Text("Preview unavailable"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .overlay {
            if let readingPreparation {
                ReadingPreparationOverlay(preparation: readingPreparation)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: readingPreparation)
        .onChange(of: viewModel.tasks) { _, _ in
            updateReadingPreparation()
        }
        .onOpenURL { url in
            openBooks([url])
        }
        .onChange(of: openBookRouter.request) { _, request in
            guard let request else { return }
            openBooks(request.urls)
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

            AppResourceImage(name: "reading-still-life")
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 360, alignment: .bottom)
                .padding(.horizontal, 4)
                .padding(.bottom, 12)
                .accessibilityHidden(true)

            Label(viewModel.canConvert ? "Ready to convert" : "Converter unavailable", systemImage: viewModel.canConvert ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(viewModel.canConvert ? MobiPalette.sage : .orange)
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

    private var failedTaskCount: Int {
        viewModel.tasks.filter { $0.status == .failed }.count
    }

    private var activeTaskCount: Int {
        viewModel.tasks.filter { [.queued, .checkingTools, .converting, .validating].contains($0.status) }.count
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
        .background(MobiPalette.paper)
    }

    private var dropZone: some View {
        AppResourceImage(name: "hero-books-background")
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 250)
            .clipped()
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
                Text("Ready")
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                Spacer()
                TaskLayoutToggle(selectedLayout: $taskLayout)
            }
            .padding(.horizontal, 30)
            .padding(.top, 18)

            ScrollView {
                LazyVGrid(columns: taskGridColumns, spacing: 14) {
                    ForEach(viewModel.tasks) { task in
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
                        } deleteHistory: {
                            viewModel.deleteTask(task)
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
                .animation(.easeInOut(duration: 0.18), value: taskLayout)
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
        }
    }

    private var taskGridColumns: [GridItem] {
        switch taskLayout {
        case .grid:
            [GridItem(.adaptive(minimum: 340, maximum: 560), spacing: 14)]
        case .list:
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
                    openBooks([url])
                }
            }
        }
    }

    private func preview(_ task: ConversionTask) {
        guard let outputURL = task.outputURL else { return }
        openEpubPreview(outputURL)
    }

    private func openBooks(_ urls: [URL]) {
        for url in urls {
            if isEpub(url) {
                readingPreparation = ReadingPreparation(
                    sourceTitle: url.deletingPathExtension().lastPathComponent,
                    message: "Opening EPUB preview",
                    progress: nil
                )
                openEpubPreview(url)
                continue
            }

            guard viewModel.acceptedExtensions.contains(url.pathExtension.lowercased()) else { continue }
            guard let task = viewModel.addFiles([url]).first else { continue }

            if let outputURL = task.outputURL,
               !viewModel.isOutputMissing(for: task),
               task.status == .succeeded || task.status == .succeededWithWarnings {
                readingPreparation = ReadingPreparation(
                    taskID: task.id,
                    sourceTitle: task.inputURL.deletingPathExtension().lastPathComponent,
                    message: "Opening converted EPUB",
                    progress: 1
                )
                openEpubPreview(outputURL)
            } else {
                readingPreparation = ReadingPreparation(
                    taskID: task.id,
                    sourceTitle: task.inputURL.deletingPathExtension().lastPathComponent,
                    message: readingMessage(for: task),
                    progress: task.progress
                )

                if task.status == .failed || viewModel.isOutputMissing(for: task) {
                    viewModel.requeueTask(task)
                }
            }
        }
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
                previewError = PreviewError(message: "The converted EPUB is no longer available at the saved output path.")
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
            previewError = PreviewError(message: task.statusMessage)
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

    private func openEpubPreview(_ outputURL: URL) {
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
                    readingPreparation = nil
                }
            } catch let error as EpubPreviewParserError {
                try? FileManager.default.removeItem(at: extractionDirectory)
                await MainActor.run {
                    readingPreparation = nil
                    previewError = PreviewError(message: error.message)
                }
            } catch {
                try? FileManager.default.removeItem(at: extractionDirectory)
                await MainActor.run {
                    readingPreparation = nil
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

private enum MobiPalette {
    static let ink = Color(red: 0.08, green: 0.16, blue: 0.20)
    static let paper = Color(red: 0.965, green: 0.948, blue: 0.91)
    static let sidebar = Color(red: 0.973, green: 0.961, blue: 0.933)
    static let cream = Color(red: 0.95, green: 0.90, blue: 0.81)
    static let sage = Color(red: 0.31, green: 0.48, blue: 0.31)
    static let terracotta = Color(red: 0.72, green: 0.28, blue: 0.16)
    static let walnut = Color(red: 0.38, green: 0.21, blue: 0.12)
    static let walnutLight = Color(red: 0.58, green: 0.36, blue: 0.22)
    static let cobalt = Color(red: 0.18, green: 0.35, blue: 0.45)
    static let mint = sage
    static let coral = terracotta
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
            Text(label)
                .font(.callout)
            Spacer()
            Text(value.formatted())
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
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
                    Text(preparation.message)
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
            guard handleSwipeChanged != nil, handleSwipeEnded != nil else {
                return event
            }
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
        .background(.white.opacity(0.32), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(MobiPalette.ink.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [7, 6]))
        }
    }
}

private enum TaskLayout: Hashable {
    case grid
    case list
}

private struct TaskLayoutToggle: View {
    @Binding var selectedLayout: TaskLayout

    var body: some View {
        HStack(spacing: 2) {
            layoutButton(layout: .grid, icon: "square.grid.2x2.fill", title: "Grid view")
            layoutButton(layout: .list, icon: "list.bullet", title: "List view")
        }
        .font(.callout)
        .padding(5)
        .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                            .fill(.white.opacity(0.9))
                            .shadow(color: MobiPalette.ink.opacity(0.08), radius: 3, y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(title)
        .accessibilityLabel(title)
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
    let deleteHistory: () -> Void

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
                TaskActionButton(title: "Preview", icon: "book.pages", enabled: canPreview, showsTitle: true, action: preview)
                TaskActionButton(title: "Reveal", icon: "folder", enabled: task.outputURL != nil && !isOutputMissing, showsTitle: true, action: revealOutput)
                TaskActionButton(title: "Report", icon: "doc.text", enabled: task.reportURL != nil, showsTitle: true, action: openReport)
                TaskActionButton(title: "Delete", icon: "trash", enabled: canDelete, role: .destructive, action: deleteHistory)
            }
        }
        .padding(14)
        .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            return "Completed \(completedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return task.statusMessage
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
                if showsTitle { Text(title) }
            }
            .font(.caption.weight(.medium))
            .frame(maxWidth: showsTitle ? .infinity : nil)
            .frame(height: 28)
            .padding(.horizontal, showsTitle ? 7 : 9)
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? MobiPalette.coral : MobiPalette.ink.opacity(0.65))
        .background(MobiPalette.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(enabled ? 1 : 0.3)
        .disabled(!enabled)
        .help(title)
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
                    ScrollViewReader { scrollProxy in
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
                            recenterCurrentPage(with: scrollProxy)
                        }
                        .onChange(of: visiblePageIndex) { _, newValue in
                            guard let newValue else { return }
                            pageIndex = min(max(newValue, 0), max(pages.count - 1, 0))
                        }
                        .onChange(of: proxy.size) { _, _ in
                            recenterCurrentPage(with: scrollProxy)
                        }
                        .onChange(of: zoom) { _, _ in
                            recenterCurrentPage(with: scrollProxy)
                        }
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

    private func recenterCurrentPage(with scrollProxy: ScrollViewProxy) {
        let currentPageIndex = min(max(pageIndex, 0), max(pages.count - 1, 0))
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                visiblePageIndex = currentPageIndex
                scrollProxy.scrollTo(currentPageIndex, anchor: .center)
            }
        }
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
