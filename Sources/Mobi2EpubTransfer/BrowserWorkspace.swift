import AppKit
import Combine
import Foundation
import Mobi2EpubTransferCore
import SwiftUI
import WebKit

struct BrowserBookmark: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var url: String

    init(id: UUID = UUID(), title: String, url: String) {
        self.id = id
        self.title = title
        self.url = url
    }
}

@MainActor
final class BrowserModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var address = ""
    @Published var pageTitle = "New tab"
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var showsHome = true
    var webView: WKWebView?

    func navigate(_ rawValue: String? = nil) {
        let value = (rawValue ?? address).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let candidate: String
        if value.contains(" ") || (!value.contains(".") && !value.contains(":")) {
            candidate = "https://duckduckgo.com/?q=" + (value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)
        } else if value.contains("://") {
            candidate = value
        } else {
            candidate = "https://" + value
        }
        guard let url = URL(string: candidate), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        showsHome = false
        address = url.absoluteString
        webView?.load(URLRequest(url: url))
    }

    func home() {
        webView?.stopLoading()
        address = ""
        pageTitle = "New tab"
        showsHome = true
    }

    func sync(from webView: WKWebView) {
        self.webView = webView
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        if let url = webView.url {
            address = url.absoluteString
            showsHome = false
        }
        pageTitle = webView.title?.isEmpty == false ? webView.title! : (webView.url?.host ?? "New tab")
    }
}

@MainActor
final class BrowserTabStore: ObservableObject {
    @Published private(set) var tabs: [BrowserModel] = []
    @Published var activeID: UUID
    private var observations: [UUID: AnyCancellable] = [:]

    init() {
        let first = BrowserModel()
        tabs = [first]
        activeID = first.id
        observe(first)
    }

    var active: BrowserModel {
        tabs.first(where: { $0.id == activeID }) ?? tabs[0]
    }

    func newTab() {
        let tab = BrowserModel()
        tabs.append(tab)
        activeID = tab.id
        observe(tab)
    }

    func close(_ id: UUID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        observations[id] = nil
        tabs.remove(at: index)
        if activeID == id { activeID = tabs[min(index, tabs.count - 1)].id }
    }

    private func observe(_ tab: BrowserModel) {
        observations[tab.id] = tab.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}

enum BrowserDownloadState: String, Codable {
    case downloading
    case paused
    case finished
    case failed
    case cancelled
}

struct BrowserDownloadItem: Identifiable, Codable {
    let id: UUID
    var filename: String
    var sourceHost: String
    var progress: Double
    var state: BrowserDownloadState
    var sourceURL: URL?
    var localURL: URL?
    var errorMessage: String?
}

@MainActor
final class BrowserDownloadManager: NSObject, ObservableObject, WKDownloadDelegate {
    @Published private(set) var items: [BrowserDownloadItem] = []
    @Published var errorMessage: String?
    var onValidatedBook: ((URL) -> Void)?

    private var downloads: [UUID: WKDownload] = [:]
    private var identifiers: [ObjectIdentifier: UUID] = [:]
    private var observations: [UUID: NSKeyValueObservation] = [:]
    private var resumeData: [UUID: Data] = [:]
    private var pausing: Set<UUID> = []
    private let defaults = UserDefaults.standard

    override init() {
        super.init()
        if let data = defaults.data(forKey: "MobiVerseBrowserRecentDownloads"),
           let restored = try? JSONDecoder().decode([BrowserDownloadItem].self, from: data) {
            items = restored.filter { $0.state == .finished }.prefix(12).map { $0 }
        }
        removeStalePartialDownloads()
    }

    var downloadDirectory: URL {
        if let data = defaults.data(forKey: "MobiVerseDownloadDirectoryBookmark") {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                return url
            }
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MobiVerse", isDirectory: true)
    }

    func setDownloadDirectory(_ url: URL) {
        guard let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        defaults.set(data, forKey: "MobiVerseDownloadDirectoryBookmark")
        objectWillChange.send()
    }

    func revealDownloads() {
        try? FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(downloadDirectory)
    }

    func begin(_ download: WKDownload, response: URLResponse, suggestedFilename: String, completion: @escaping (URL?) -> Void) {
        let filename = sanitizedFilename(suggestedFilename, response: response)
        let id = identifiers[ObjectIdentifier(download)] ?? UUID()
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].filename = filename
            items[index].state = .downloading
            items[index].errorMessage = nil
        } else {
            let item = BrowserDownloadItem(
                id: id,
                filename: filename,
                sourceHost: response.url?.host ?? download.originalRequest?.url?.host ?? "Unknown source",
                progress: 0,
                state: .downloading,
                sourceURL: download.originalRequest?.url
            )
            items.insert(item, at: 0)
        }
        downloads[id] = download
        identifiers[ObjectIdentifier(download)] = id
        observeProgress(of: download, id: id)
        let partialDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MobiVerseBrowserDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: partialDirectory, withIntermediateDirectories: true)
        let partial = partialDirectory.appendingPathComponent("\(id.uuidString)-\(filename).download")
        try? FileManager.default.removeItem(at: partial)
        completion(partial)
    }

    func finished(_ download: WKDownload) {
        guard let id = identifiers[ObjectIdentifier(download)], let index = items.firstIndex(where: { $0.id == id }) else { return }
        let partialDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MobiVerseBrowserDownloads", isDirectory: true)
        let partial = partialDirectory.appendingPathComponent("\(id.uuidString)-\(items[index].filename).download")
        do {
            let verifiedExtension = try DownloadedBookValidator.validatedExtension(
                at: partial,
                suggestedExtension: URL(fileURLWithPath: items[index].filename).pathExtension
            )
            try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
            let base = URL(fileURLWithPath: items[index].filename).deletingPathExtension().lastPathComponent
            let destination = availableDestination(baseName: base, extension: verifiedExtension)
            try FileManager.default.moveItem(at: partial, to: destination)
            items[index].filename = destination.lastPathComponent
            items[index].localURL = destination
            items[index].progress = 1
            items[index].state = .finished
            persistRecent()
            cleanup(id: id, download: download)
            onValidatedBook?(destination)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            items[index].state = .failed
            items[index].errorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            cleanup(id: id, download: download)
        }
    }

    func failed(_ download: WKDownload, error: Error) {
        guard let id = identifiers[ObjectIdentifier(download)], let index = items.firstIndex(where: { $0.id == id }) else { return }
        if pausing.contains(id) {
            items[index].state = .paused
            pausing.remove(id)
            cleanup(id: id, download: download)
            return
        }
        items[index].state = (error as NSError).code == NSURLErrorCancelled ? .cancelled : .failed
        items[index].errorMessage = error.localizedDescription
        cleanup(id: id, download: download)
    }

    func cancel(_ item: BrowserDownloadItem) {
        if let download = downloads[item.id] {
            download.cancel()
        } else if resumeData[item.id] != nil {
            resumeData[item.id] = nil
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].state = .cancelled
            }
        }
    }

    func pause(_ item: BrowserDownloadItem) {
        guard let download = downloads[item.id] else { return }
        pausing.insert(item.id)
        download.cancel { [weak self] data in
            guard let self, let data else { return }
            self.resumeData[item.id] = data
            if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                self.items[index].state = .paused
            }
        }
    }

    func resume(_ item: BrowserDownloadItem, in webView: WKWebView?) {
        guard let data = resumeData[item.id], let webView else { return }
        webView.resumeDownload(fromResumeData: data) { [weak self] download in
            guard let self else { return }
            self.resumeData[item.id] = nil
            self.downloads[item.id] = download
            self.identifiers[ObjectIdentifier(download)] = item.id
            download.delegate = self
            if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                self.items[index].state = .downloading
                self.items[index].errorMessage = nil
            }
            self.observeProgress(of: download, id: item.id)
        }
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor (URL?) -> Void
    ) {
        begin(download, response: response, suggestedFilename: suggestedFilename, completion: completionHandler)
    }

    func downloadDidFinish(_ download: WKDownload) { finished(download) }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        failed(download, error: error)
    }

    private func update(id: UUID, progress: Double) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].progress = progress
    }

    private func observeProgress(of download: WKDownload, id: UUID) {
        observations[id] = download.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            Task { @MainActor in self?.update(id: id, progress: progress.fractionCompleted) }
        }
    }

    private func cleanup(id: UUID, download: WKDownload) {
        observations[id] = nil
        downloads[id] = nil
        identifiers[ObjectIdentifier(download)] = nil
    }

    private func sanitizedFilename(_ value: String, response: URLResponse) -> String {
        var name = URL(fileURLWithPath: value).lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        if name.isEmpty { name = "Downloaded book" }
        if URL(fileURLWithPath: name).pathExtension.isEmpty,
           let type = response.mimeType?.lowercased() {
            let ext = ["application/epub+zip": "epub", "application/pdf": "pdf", "application/x-mobipocket-ebook": "mobi", "application/zip": "zip"][type]
            if let ext { name += ".\(ext)" }
        }
        return String(name.prefix(180))
    }

    private func availableDestination(baseName: String, extension ext: String) -> URL {
        var candidate = downloadDirectory.appendingPathComponent(baseName).appendingPathExtension(ext)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = downloadDirectory.appendingPathComponent("\(baseName) \(number)").appendingPathExtension(ext)
            number += 1
        }
        return candidate
    }

    private func persistRecent() {
        let finished = items.filter { $0.state == .finished }.prefix(12)
        defaults.set(try? JSONEncoder().encode(Array(finished)), forKey: "MobiVerseBrowserRecentDownloads")
    }

    private func removeStalePartialDownloads() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MobiVerseBrowserDownloads", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }
}

struct BrowserWorkspace: View {
    @ObservedObject var tabs: BrowserTabStore
    @ObservedObject var downloads: BrowserDownloadManager
    @AppStorage(BrowserPDFHandling.storageKey) private var pdfHandlingRawValue = BrowserPDFHandling.download.rawValue
    @State private var bookmarks: [BrowserBookmark] = Self.loadBookmarks()
    @State private var showsDownloads = true
    @State private var showsSettings = false
    let onBookDownloaded: (URL) -> Void

    private var model: BrowserModel { tabs.active }
    private var pdfHandling: BrowserPDFHandling {
        BrowserPDFHandling(rawValue: pdfHandlingRawValue) ?? .download
    }
    private var addressBinding: Binding<String> {
        Binding(get: { model.address }, set: { model.address = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            browserToolbar
            if !bookmarks.isEmpty {
                bookmarkBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ZStack {
                BrowserWebView(
                    model: model,
                    downloads: downloads,
                    automaticallyDownloadsPDFs: pdfHandling == .download
                )
                if model.showsHome { homePage }
            }
            if showsDownloads { downloadShelf }
        }
        .foregroundStyle(BrowserPalette.ink)
        .background(BrowserPalette.paper)
        .animation(.easeInOut(duration: 0.18), value: bookmarks)
        .onAppear { downloads.onValidatedBook = onBookDownloaded }
        .sheet(isPresented: $showsSettings) {
            BrowserSettingsView(
                bookmarks: $bookmarks,
                downloads: downloads,
                pdfHandlingRawValue: $pdfHandlingRawValue
            ) {
                saveBookmarks()
            }
        }
        .alert("Download unavailable", isPresented: Binding(get: { downloads.errorMessage != nil }, set: { if !$0 { downloads.errorMessage = nil } })) {
            Button("OK", role: .cancel) { downloads.errorMessage = nil }
        } message: { Text(downloads.errorMessage ?? "") }
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tabs.tabs) { tab in
                        HStack(spacing: 7) {
                            Button {
                                tabs.activeID = tab.id
                            } label: {
                                Label(tab.pageTitle, systemImage: "globe")
                                    .lineLimit(1)
                                    .frame(maxWidth: 180, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            if tabs.tabs.count > 1 {
                                Button { tabs.close(tab.id) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(
                            tab.id == tabs.activeID ? BrowserPalette.surfaceRaised : BrowserPalette.surface.opacity(0.46),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            Button { tabs.newTab() } label: { Image(systemName: "plus") }
                .help("New tab")
            Spacer()
            Button { showsDownloads.toggle() } label: { Label("Downloads", systemImage: "arrow.down.circle") }
            Button { showsSettings = true } label: { Image(systemName: "gearshape") }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(BrowserPalette.sidebar)
    }

    private var browserToolbar: some View {
        HStack(spacing: 9) {
            Button { model.webView?.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!model.canGoBack)
            Button { model.webView?.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!model.canGoForward)
            Button {
                if model.isLoading { model.webView?.stopLoading() }
                else { _ = model.webView?.reload() }
            } label: { Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise") }
            Button { model.home() } label: { Image(systemName: "house") }
            TextField("Search or enter address", text: addressBinding)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.navigate() }
            Button(action: toggleBookmark) {
                Image(systemName: isCurrentPageBookmarked ? "star.fill" : "star")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isCurrentPageBookmarked ? BrowserPalette.terracotta : BrowserPalette.ink.opacity(0.62))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 24, height: 24)
            }
            .disabled(currentPageURL == nil)
            .help(isCurrentPageBookmarked ? "Remove bookmark" : "Bookmark this page")
            .accessibilityLabel(isCurrentPageBookmarked ? "Remove bookmark" : "Bookmark this page")
        }
        .buttonStyle(.borderless)
        .padding(10)
        .background(.ultraThinMaterial)
    }

    private var bookmarkBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "bookmark.fill")
                .font(.caption)
                .foregroundStyle(BrowserPalette.terracotta.opacity(0.78))
                .accessibilityHidden(true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(bookmarks) { bookmark in
                        Button {
                            model.navigate(bookmark.url)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "globe")
                                    .font(.caption2)
                                    .foregroundStyle(BrowserPalette.sage)
                                Text(bookmark.title.isEmpty ? bookmarkHost(bookmark) : bookmark.title)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text(bookmarkHost(bookmark))
                                    .font(.caption2)
                                    .foregroundStyle(BrowserPalette.ink.opacity(0.48))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(
                                isBookmarkCurrentPage(bookmark) ? BrowserPalette.cream.opacity(0.82) : BrowserPalette.surface.opacity(0.68),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .stroke(BrowserPalette.ink.opacity(0.07), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(bookmark.url)
                    }
                }
            }

            Button {
                showsSettings = true
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(BrowserPalette.ink.opacity(0.52))
            .help("Manage bookmarks")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(BrowserPalette.sidebar.opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrowserPalette.ink.opacity(0.07))
                .frame(height: 1)
        }
    }

    private var homePage: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "books.vertical.fill").font(.system(size: 48)).foregroundStyle(BrowserPalette.sage)
                Text("Find your next book").font(.system(size: 32, weight: .semibold, design: .serif))
                TextField("Search the web or enter a website", text: addressBinding)
                    .textFieldStyle(.roundedBorder).font(.title3).frame(maxWidth: 620)
                    .onSubmit { model.navigate() }
                if !bookmarks.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(bookmarks) { bookmark in
                            Button { model.navigate(bookmark.url) } label: {
                                VStack(spacing: 9) {
                                    Image(systemName: "bookmark.fill").foregroundStyle(BrowserPalette.terracotta)
                                    Text(bookmark.title).lineLimit(1)
                                    Text(URL(string: bookmark.url)?.host ?? bookmark.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity).padding(16)
                                .background(BrowserPalette.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain)
                        }
                    }.frame(maxWidth: 720)
                }
                Label("Download only books you have the right to access. MobiVerse does not bypass DRM or website restrictions.", systemImage: "hand.raised.fill")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(54).frame(maxWidth: .infinity)
        }.background(BrowserPalette.paper)
    }

    private var downloadShelf: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                Button("Show in Finder") { downloads.revealDownloads() }
            }.padding(.horizontal, 16).padding(.vertical, 8)
            if downloads.items.isEmpty {
                Text("Downloaded books will appear here and be analyzed before conversion.").font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(downloads.items.prefix(8)) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.filename).font(.caption.weight(.semibold)).lineLimit(1)
                                Text(item.sourceHost).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                if item.state == .downloading { ProgressView(value: item.progress) }
                                else { Text(item.state.rawValue.capitalized).font(.caption2).foregroundStyle(item.state == .finished ? .green : .red) }
                                HStack(spacing: 8) {
                                    if item.state == .downloading {
                                        Button("Pause") { downloads.pause(item) }
                                        Button("Cancel") { downloads.cancel(item) }
                                    } else if item.state == .paused {
                                        Button("Resume") { downloads.resume(item, in: model.webView) }
                                        Button("Cancel") { downloads.cancel(item) }
                                    } else if item.state == .failed || item.state == .cancelled, let url = item.sourceURL {
                                        Button("Retry") { model.navigate(url.absoluteString) }
                                    } else if item.state == .finished, let url = item.localURL {
                                        Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                    }
                                }
                                .buttonStyle(.borderless)
                                .font(.caption2)
                            }.frame(width: 190, alignment: .leading)
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 10)
                }
            }
        }.background(BrowserPalette.sidebar)
    }

    private var currentPageURL: URL? {
        guard !model.showsHome else { return nil }
        let candidate = model.webView?.url ?? URL(string: model.address)
        guard
            let candidate,
            ["http", "https"].contains(candidate.scheme?.lowercased() ?? "")
        else {
            return nil
        }
        return candidate
    }

    private var currentBookmarkIndex: Int? {
        guard let currentPageURL else { return nil }
        let current = canonicalBookmarkURL(currentPageURL)
        return bookmarks.firstIndex { bookmark in
            guard let url = URL(string: bookmark.url) else { return false }
            return canonicalBookmarkURL(url) == current
        }
    }

    private var isCurrentPageBookmarked: Bool {
        currentBookmarkIndex != nil
    }

    private func toggleBookmark() {
        guard let currentPageURL else { return }
        if let index = currentBookmarkIndex {
            bookmarks.remove(at: index)
        } else {
            let title = model.pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            bookmarks.append(
                BrowserBookmark(
                    title: title.isEmpty ? (currentPageURL.host ?? "Saved page") : title,
                    url: canonicalBookmarkURL(currentPageURL)
                )
            )
        }
        saveBookmarks()
    }

    private func isBookmarkCurrentPage(_ bookmark: BrowserBookmark) -> Bool {
        guard
            let currentPageURL,
            let bookmarkURL = URL(string: bookmark.url)
        else {
            return false
        }
        return canonicalBookmarkURL(currentPageURL) == canonicalBookmarkURL(bookmarkURL)
    }

    private func canonicalBookmarkURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.fragment = nil
        return components.url?.absoluteString ?? url.absoluteString
    }

    private func bookmarkHost(_ bookmark: BrowserBookmark) -> String {
        URL(string: bookmark.url)?.host ?? bookmark.url
    }

    private func saveBookmarks() { UserDefaults.standard.set(try? JSONEncoder().encode(bookmarks), forKey: "MobiVerseBrowserBookmarks") }
    private static func loadBookmarks() -> [BrowserBookmark] {
        guard let data = UserDefaults.standard.data(forKey: "MobiVerseBrowserBookmarks") else { return [] }
        return (try? JSONDecoder().decode([BrowserBookmark].self, from: data)) ?? []
    }
}

private struct BrowserWebView: NSViewRepresentable {
    @ObservedObject var model: BrowserModel
    @ObservedObject var downloads: BrowserDownloadManager
    let automaticallyDownloadsPDFs: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            model: model,
            downloads: downloads,
            automaticallyDownloadsPDFs: automaticallyDownloadsPDFs
        )
    }
    func makeNSView(context: Context) -> WKWebView {
        if let view = model.webView {
            view.navigationDelegate = context.coordinator
            view.uiDelegate = context.coordinator
            return view
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        model.webView = view
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.automaticallyDownloadsPDFs = automaticallyDownloadsPDFs
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: BrowserModel
        let downloads: BrowserDownloadManager
        var automaticallyDownloadsPDFs: Bool
        init(model: BrowserModel, downloads: BrowserDownloadManager, automaticallyDownloadsPDFs: Bool) {
            self.model = model
            self.downloads = downloads
            self.automaticallyDownloadsPDFs = automaticallyDownloadsPDFs
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { model.sync(from: webView) }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { model.sync(from: webView) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { model.sync(from: webView) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { model.sync(from: webView) }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            let scheme = url.scheme?.lowercased() ?? ""
            guard ["http", "https", "about"].contains(scheme) else {
                let alert = NSAlert()
                alert.messageText = "Open external application?"
                alert.informativeText = url.absoluteString
                alert.addButton(withTitle: "Open")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
                return
            }
            if navigationAction.shouldPerformDownload { decisionHandler(.download) } else { decisionHandler(.allow) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
            let response = navigationResponse.response
            let info = BrowserNavigationResponseInfo(
                url: response.url,
                mimeType: response.mimeType,
                suggestedFilename: response.suggestedFilename,
                contentDisposition: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition"),
                isForMainFrame: navigationResponse.isForMainFrame,
                canShowMIMEType: navigationResponse.canShowMIMEType
            )
            let shouldDownload = BrowserDownloadPolicy.shouldDownload(
                info,
                automaticallyDownloadsPDFs: automaticallyDownloadsPDFs
            )
            decisionHandler(shouldDownload ? .download : .allow)
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = downloads }
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = downloads }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }
    }
}

private struct BrowserSettingsView: View {
    @Binding var bookmarks: [BrowserBookmark]
    @ObservedObject var downloads: BrowserDownloadManager
    @Binding var pdfHandlingRawValue: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsClearConfirmation = false
    @State private var privacyMessage: String?
    @State private var selectedSection = BrowserSettingsSection.downloads

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader

            HStack(spacing: 0) {
                settingsNavigation

                Rectangle()
                    .fill(BrowserPalette.ink.opacity(0.08))
                    .frame(width: 1)

                ScrollView {
                    Group {
                        switch selectedSection {
                        case .downloads:
                            downloadCard
                        case .bookmarks:
                            bookmarkCard
                        case .privacy:
                            privacyCard
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .foregroundStyle(BrowserPalette.ink)
        .background(BrowserPalette.paper)
        .frame(width: 700, height: 500)
        .fixedSize()
        .onDisappear(perform: onSave)
        .alert("Clear browser data?", isPresented: $showsClearConfirmation) {
            Button("Clear browsing data", role: .destructive, action: clearBrowserData)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Cookies, website cache, and browsing history will be removed. Downloaded books, conversion history, and bookmarks will stay untouched.")
        }
    }

    private var settingsNavigation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BROWSER")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(BrowserPalette.ink.opacity(0.43))
                .padding(.horizontal, 11)
                .padding(.bottom, 3)

            ForEach(BrowserSettingsSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selectedSection == section ? section.accent : BrowserPalette.ink.opacity(0.52))
                            .frame(width: 20)
                        Text(section.title)
                            .font(.callout.weight(selectedSection == section ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 38)
                    .contentShape(Rectangle())
                    .background(
                        selectedSection == section ? BrowserPalette.surfaceRaised : .clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(BrowserPalette.sage)
                Text("Private by design")
                    .font(.caption.weight(.semibold))
                Text("Browser data and book analysis stay on this Mac.")
                    .font(.caption2)
                    .foregroundStyle(BrowserPalette.ink.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(11)
        }
        .padding(16)
        .frame(width: 174)
        .background(BrowserPalette.sidebar.opacity(0.76))
    }

    private var settingsHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(BrowserPalette.cream)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(BrowserPalette.sage)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 3) {
                Text("Browser settings")
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                Text("Shape a calm, private space for finding your next book.")
                    .font(.callout)
                    .foregroundStyle(BrowserPalette.ink.opacity(0.58))
            }

            Spacer()

            Button {
                onSave()
                dismiss()
            } label: {
                Text("Done")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(MobiPalette.onAccent)
                    .padding(.horizontal, 17)
                    .frame(height: 34)
                    .background(BrowserPalette.sage, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: BrowserPalette.sage.opacity(0.18), radius: 6, y: 2)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(BrowserPalette.sidebar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrowserPalette.ink.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var downloadCard: some View {
        BrowserSettingsCard(
            icon: "arrow.down.circle.fill",
            accent: BrowserPalette.sage,
            title: "Download location",
            subtitle: "New books are verified here before they enter your shelf."
        ) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(BrowserPalette.walnutLight)
                    Text(downloads.downloadDirectory.path)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 13)
                .frame(height: 40)
                .background(BrowserPalette.cream.opacity(0.56), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(BrowserPalette.walnut.opacity(0.11), lineWidth: 1)
                }

                HStack(spacing: 10) {
                    Button(action: chooseFolder) {
                        Label("Choose folder…", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .tint(BrowserPalette.sage)

                    Button {
                        downloads.revealDownloads()
                    } label: {
                        Label("Show in Finder", systemImage: "finder")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(BrowserPalette.cobalt)
                }

                Divider().overlay(BrowserPalette.ink.opacity(0.08))

                VStack(alignment: .leading, spacing: 8) {
                    Text("PDF links")
                        .font(.callout.weight(.semibold))
                    Picker("PDF links", selection: $pdfHandlingRawValue) {
                        ForEach(BrowserPDFHandling.allCases) { handling in
                            Text(handling.title).tag(handling.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    Text("Automatic downloads keep the current website session and send verified PDFs directly to import review.")
                        .font(.caption)
                        .foregroundStyle(BrowserPalette.ink.opacity(0.56))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var bookmarkCard: some View {
        BrowserSettingsCard(
            icon: "bookmark.fill",
            accent: BrowserPalette.terracotta,
            title: "Bookmarks",
            subtitle: bookmarks.isEmpty
                ? "Keep trusted libraries and reading sources close at hand."
                : "\(bookmarks.count) saved \(bookmarks.count == 1 ? "destination" : "destinations") on your browser home page."
        ) {
            VStack(spacing: 10) {
                if bookmarks.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "bookmark.slash")
                            .font(.title3)
                            .foregroundStyle(BrowserPalette.terracotta.opacity(0.72))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No bookmarks yet")
                                .font(.callout.weight(.semibold))
                            Text("Add one here, or use the star button while browsing.")
                                .font(.caption)
                                .foregroundStyle(BrowserPalette.ink.opacity(0.56))
                        }
                        Spacer()
                    }
                    .padding(13)
                    .background(BrowserPalette.cream.opacity(0.42), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                } else {
                    ForEach($bookmarks) { $bookmark in
                        bookmarkRow(bookmark: $bookmark)
                    }
                }

                Button {
                    bookmarks.append(BrowserBookmark(title: "New bookmark", url: "https://"))
                } label: {
                    Label("Add bookmark", systemImage: "plus")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(BrowserPalette.terracotta)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            }
        }
    }

    private func bookmarkRow(bookmark: Binding<BrowserBookmark>) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(BrowserPalette.terracotta.opacity(0.82))
                .frame(width: 22)

            VStack(spacing: 7) {
                TextField("Bookmark title", text: bookmark.title)
                    .font(.callout.weight(.medium))
                    .textFieldStyle(.plain)
                Divider().overlay(BrowserPalette.ink.opacity(0.08))
                TextField("https://example.com", text: bookmark.url)
                    .font(.caption.monospaced())
                    .textFieldStyle(.plain)
                    .foregroundStyle(BrowserPalette.ink.opacity(0.68))
            }

            Button(role: .destructive) {
                bookmarks.removeAll { $0.id == bookmark.wrappedValue.id }
            } label: {
                Image(systemName: "trash")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(BrowserPalette.terracotta.opacity(0.78))
            .help("Remove bookmark")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(BrowserPalette.surface.opacity(0.74), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(BrowserPalette.ink.opacity(0.08), lineWidth: 1)
        }
    }

    private var privacyCard: some View {
        BrowserSettingsCard(
            icon: "hand.raised.fill",
            accent: BrowserPalette.cobalt,
            title: "Privacy",
            subtitle: "Reset website sessions without touching your books or shelf."
        ) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Website data")
                        .font(.callout.weight(.semibold))
                    Text(privacyMessage ?? "Clears cookies, cached files, and browsing history.")
                        .font(.caption)
                        .foregroundStyle(privacyMessage == nil ? BrowserPalette.ink.opacity(0.56) : BrowserPalette.sage)
                }
                Spacer()
                Button(role: .destructive) {
                    showsClearConfirmation = true
                } label: {
                    Text("Clear data…")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(BrowserPalette.terracotta)
                        .padding(.horizontal, 13)
                        .frame(height: 32)
                        .background(BrowserPalette.terracotta.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(BrowserPalette.terracotta.opacity(0.18), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(13)
            .background(BrowserPalette.cream.opacity(0.42), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { downloads.setDownloadDirectory(url) }
    }

    private func clearBrowserData() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
            Task { @MainActor in
                privacyMessage = "Browser data cleared. Your books and bookmarks are safe."
            }
        }
    }
}

private enum BrowserPDFHandling: String, CaseIterable, Identifiable {
    static let storageKey = "MobiVerseBrowserPDFHandling"

    case download
    case preview

    var id: String { rawValue }
    var title: String {
        switch self {
        case .download: "Download automatically"
        case .preview: "Preview in browser"
        }
    }
}

private enum BrowserSettingsSection: String, CaseIterable, Identifiable {
    case downloads
    case bookmarks
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloads: "Downloads"
        case .bookmarks: "Bookmarks"
        case .privacy: "Privacy"
        }
    }

    var icon: String {
        switch self {
        case .downloads: "arrow.down.circle.fill"
        case .bookmarks: "bookmark.fill"
        case .privacy: "hand.raised.fill"
        }
    }

    var accent: Color {
        switch self {
        case .downloads: BrowserPalette.sage
        case .bookmarks: BrowserPalette.terracotta
        case .privacy: BrowserPalette.cobalt
        }
    }
}

private struct BrowserSettingsCard<Content: View>: View {
    let icon: String
    let accent: Color
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.12))
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(BrowserPalette.ink.opacity(0.56))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            content
        }
        .padding(18)
        .background(BrowserPalette.surface.opacity(0.90), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(BrowserPalette.ink.opacity(0.09), lineWidth: 1)
        }
        .shadow(color: BrowserPalette.ink.opacity(0.06), radius: 12, y: 5)
    }
}

private enum BrowserPalette {
    static let ink = MobiPalette.ink
    static let paper = MobiPalette.paper
    static let sidebar = MobiPalette.sidebar
    static let cream = MobiPalette.cream
    static let surface = MobiPalette.surface
    static let surfaceRaised = MobiPalette.surfaceRaised
    static let sage = MobiPalette.sage
    static let terracotta = MobiPalette.terracotta
    static let walnut = MobiPalette.walnut
    static let walnutLight = MobiPalette.walnutLight
    static let cobalt = MobiPalette.cobalt
}
