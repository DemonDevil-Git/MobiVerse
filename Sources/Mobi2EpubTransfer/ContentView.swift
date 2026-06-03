import Mobi2EpubTransferCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = ConversionViewModel()
    @State private var isSidebarVisible = true
    @State private var isToolStatusPresented = false

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
