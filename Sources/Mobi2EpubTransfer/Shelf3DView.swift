import AppKit
import Mobi2EpubTransferCore
import SwiftUI

struct Shelf3DView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let tasks: [ConversionTask]
    let coverImage: (ConversionTask) -> NSImage?
    let metadata: (ConversionTask) -> EpubBookMetadata?
    let isOutputMissing: (ConversionTask) -> Bool
    let requestAssets: (ConversionTask) -> Void
    let addBooks: () -> Void
    let preview: (ConversionTask) -> Void
    let revealOutput: (ConversionTask) -> Void
    let openReport: (ConversionTask) -> Void
    let deleteOutput: (ConversionTask) -> Void

    @State private var selectedID: UUID?
    @State private var detailID: UUID?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                stageBackdrop

                if tasks.isEmpty {
                    emptyShelf
                } else {
                    Shelf3DStageView(
                        items: stageItems,
                        selectedID: selectedID,
                        isDetailPresented: detailID != nil,
                        reduceMotion: reduceMotion,
                        isDark: colorScheme == .dark,
                        onSelect: select,
                        onOpen: presentDetails,
                        onStep: moveSelection,
                        onClose: dismissDetails
                    )
                    .accessibilityHidden(true)

                    if detailID == nil {
                        browsingSummary(maximumWidth: browsingSummaryWidth(for: proxy.size.width))
                            .transition(.opacity)
                    }

                    if let detailTask {
                        detailPane(for: detailTask)
                            .frame(width: min(430, max(330, proxy.size.width * 0.43)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                            .padding(.trailing, 28)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }

                    if detailID == nil {
                        browsingControls
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .onAppear(perform: synchronizeSelection)
        .onChange(of: tasks) { _, _ in synchronizeSelection() }
        .task(id: selectedID) {
            guard let selectedID else { return }
            if !reduceMotion {
                // Keep high-resolution cover and metadata decoding outside the
                // selection spring animation so uncached books remain smooth.
                try? await Task.sleep(for: .milliseconds(820))
            }
            guard
                !Task.isCancelled,
                let task = tasks.first(where: { $0.id == selectedID })
            else {
                return
            }
            requestAssets(task)
        }
        .animation(detailAnimation, value: detailID)
        .animation(.easeOut(duration: 0.22), value: selectedID)
    }

    private var stageBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [
                    MobiPalette.surface.opacity(colorScheme == .dark ? 0.74 : 0.88),
                    MobiPalette.paper.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [MobiPalette.cream.opacity(colorScheme == .dark ? 0.10 : 0.44), .clear],
                center: UnitPoint(x: 0.34, y: 0.43),
                startRadius: 24,
                endRadius: 360
            )

            VStack {
                Spacer()
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, MobiPalette.ink.opacity(0.055), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 72)
            }
        }
    }

    private var emptyShelf: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(MobiPalette.sage.opacity(0.72))
            Text("Your 3D shelf is ready")
                .font(.system(size: 25, weight: .semibold, design: .serif))
            Text("Add a book to place it on the shelf.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(action: addBooks) {
                Label("Choose books", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(MobiPalette.sage)
            .padding(.top, 4)
        }
        .foregroundStyle(MobiPalette.ink)
    }

    private func browsingSummary(maximumWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedMetadata?.title.nonEmpty ?? selectedTask?.displayTitle ?? "Your shelf")
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .lineLimit(4)
                .minimumScaleFactor(0.82)
                .contentTransition(.opacity)

            if let creatorLine = selectedMetadata?.creatorLine.nonEmpty {
                Text(creatorLine)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(MobiPalette.terracotta)
                    .lineLimit(2)
            }

            if let task = selectedTask {
                ShelfStatusCapsule(task: task, isMissing: isOutputMissing(task))
            }

            Text("Scroll, swipe, or use the arrow keys to browse")
                .font(.caption)
                .foregroundStyle(MobiPalette.ink.opacity(0.46))
                .padding(.top, 4)
        }
        .foregroundStyle(MobiPalette.ink)
        .frame(width: maximumWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.leading, 28)
        .padding(.top, 34)
        .id(selectedID)
        .accessibilityElement(children: .combine)
    }

    private func browsingSummaryWidth(for stageWidth: CGFloat) -> CGFloat {
        min(190, max(120, stageWidth * 0.22))
    }

    private var browsingControls: some View {
        HStack(spacing: 10) {
            Button { moveSelection(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .help("Previous book")

            Text(selectionCounter)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(MobiPalette.ink.opacity(0.54))
                .frame(minWidth: 54)

            Button { moveSelection(1) } label: {
                Image(systemName: "chevron.right")
            }
            .help("Next book")

            Divider().frame(height: 20)

            Button {
                if let selectedID { presentDetails(selectedID) }
            } label: {
                Label("Book details", systemImage: "view.3d")
            }
            .disabled(selectedTask == nil)

            Button(action: addBooks) {
                Label("Add books", systemImage: "plus")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(MobiPalette.ink.opacity(0.07)) }
        .shadow(color: MobiPalette.ink.opacity(0.10), radius: 14, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 18)
        .accessibilityElement(children: .contain)
    }

    private func detailPane(for task: ConversionTask) -> some View {
        let bookMetadata = metadata(task)
        let missing = isOutputMissing(task)

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Book details")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MobiPalette.terracotta)
                    .textCase(.uppercase)
                    .tracking(1.1)
                Spacer()
                Button(action: dismissDetails) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(MobiPalette.ink.opacity(0.06), in: Circle())
                .help("Return to shelf")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(bookMetadata?.title.nonEmpty ?? task.displayTitle)
                        .font(.system(size: 29, weight: .semibold, design: .serif))
                        .foregroundStyle(MobiPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if let creatorLine = bookMetadata?.creatorLine.nonEmpty {
                        Text(creatorLine)
                            .font(.headline.weight(.medium))
                            .foregroundStyle(MobiPalette.terracotta)
                            .padding(.top, 7)
                    }

                    ShelfStatusCapsule(task: task, isMissing: missing)
                        .padding(.top, 12)

                    if let description = bookMetadata?.description?.nonEmpty {
                        Text(description)
                            .font(.callout)
                            .foregroundStyle(MobiPalette.ink.opacity(0.66))
                            .lineSpacing(3)
                            .lineLimit(6)
                            .padding(.top, 16)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                        detailFact("Format", task.outputURL?.pathExtension.uppercased() ?? task.inputURL.pathExtension.uppercased())
                        detailFact("Size", fileSizeDescription(for: task))
                        detailFact("Type", contentKindDescription(for: task))
                        detailFact("Reading", task.readingDirection == .rightToLeft ? "Right to left" : "Left to right")
                        if let publisher = bookMetadata?.publisher?.nonEmpty {
                            detailFact("Publisher", publisher)
                        }
                        if let language = bookMetadata?.language?.nonEmpty {
                            detailFact("Language", language)
                        }
                    }
                    .padding(.top, 18)
                }
                .padding(.vertical, 16)
            }
            .scrollIndicators(.never)

            Text("Drag the book to inspect its cover, spine, pages, and back.")
                .font(.caption)
                .foregroundStyle(MobiPalette.ink.opacity(0.44))
                .lineLimit(1)
                .padding(.bottom, 10)

            HStack(spacing: 8) {
                detailAction("Preview", icon: "book.pages", enabled: task.canPreview && !missing) { preview(task) }
                detailAction("Reveal", icon: "folder", enabled: task.outputURL != nil && !missing) { revealOutput(task) }
                detailAction("Report", icon: "doc.text", enabled: task.reportURL != nil) { openReport(task) }
                detailAction("Delete", icon: "trash", enabled: task.canDelete, destructive: true) { deleteOutput(task) }
            }
        }
        .padding(20)
        .background(MobiPalette.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(MobiPalette.ink.opacity(0.075))
        }
        .shadow(color: MobiPalette.ink.opacity(0.11), radius: 24, y: 10)
        .padding(.vertical, 28)
        .accessibilityElement(children: .contain)
    }

    private func detailFact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.string(label).uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(MobiPalette.ink.opacity(0.38))
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(MobiPalette.ink.opacity(0.72))
                .lineLimit(2)
        }
    }

    private func detailAction(
        _ title: String,
        icon: String,
        enabled: Bool,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(L10n.string(title)).font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .foregroundStyle(destructive ? MobiPalette.coral : MobiPalette.ink.opacity(0.72))
            .background(MobiPalette.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.28)
        .help(L10n.string(title))
    }

    private var stageItems: [Shelf3DItem] {
        tasks.map { task in
            Shelf3DItem(
                id: task.id,
                title: metadata(task)?.title.nonEmpty ?? task.displayTitle,
                coverImage: coverImage(task),
                isDimmed: isOutputMissing(task)
            )
        }
    }

    private var selectedTask: ConversionTask? {
        guard let selectedID else { return tasks.first }
        return tasks.first { $0.id == selectedID }
    }

    private var detailTask: ConversionTask? {
        guard let detailID else { return nil }
        return tasks.first { $0.id == detailID }
    }

    private var selectedMetadata: EpubBookMetadata? {
        selectedTask.flatMap(metadata)
    }

    private var selectionCounter: String {
        guard let selectedID, let index = tasks.firstIndex(where: { $0.id == selectedID }) else { return "0 / 0" }
        return "\(index + 1) / \(tasks.count)"
    }

    private var detailAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.72, dampingFraction: 0.88)
    }

    private func synchronizeSelection() {
        guard !tasks.isEmpty else {
            selectedID = nil
            detailID = nil
            return
        }
        if let selectedID, tasks.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = tasks.first?.id
        if let detailID, !tasks.contains(where: { $0.id == detailID }) {
            self.detailID = nil
        }
    }

    private func select(_ id: UUID) {
        guard tasks.contains(where: { $0.id == id }) else { return }
        detailID = nil
        selectedID = id
    }

    private func presentDetails(_ id: UUID) {
        guard tasks.contains(where: { $0.id == id }) else { return }
        selectedID = id
        detailID = id
        if let task = tasks.first(where: { $0.id == id }) { requestAssets(task) }
    }

    private func dismissDetails() {
        detailID = nil
    }

    private func moveSelection(_ offset: Int) {
        guard !tasks.isEmpty else { return }
        let currentIndex = selectedID.flatMap { id in tasks.firstIndex(where: { $0.id == id }) } ?? 0
        let nextIndex = (currentIndex + offset + tasks.count) % tasks.count
        detailID = nil
        selectedID = tasks[nextIndex].id
    }

    private func fileSizeDescription(for task: ConversionTask) -> String {
        let url = task.outputURL ?? task.inputURL
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber
        else {
            return L10n.string("Unavailable")
        }
        return ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
    }

    private func contentKindDescription(for task: ConversionTask) -> String {
        switch task.detectedKind {
        case .text: L10n.string("Text")
        case .comic: L10n.string("Comic")
        case .uncertain, nil: L10n.string("Book")
        }
    }

}

private struct ShelfStatusCapsule: View {
    let task: ConversionTask
    let isMissing: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(L10n.string(isMissing ? "File unavailable" : task.status.displayName))
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(MobiPalette.ink.opacity(0.66))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(MobiPalette.ink.opacity(0.045), in: Capsule())
    }

    private var color: Color {
        if isMissing { return MobiPalette.coral }
        switch task.status {
        case .failed: return MobiPalette.coral
        case .succeededWithWarnings: return .orange
        case .succeeded: return MobiPalette.sage
        case .queued, .checkingTools, .converting, .validating: return MobiPalette.cobalt
        }
    }
}

private extension ConversionTask {
    var displayTitle: String {
        inputURL.deletingPathExtension().lastPathComponent
    }

    var canPreview: Bool {
        (status == .succeeded || status == .succeededWithWarnings) && outputURL != nil
    }

    var canDelete: Bool {
        switch status {
        case .checkingTools, .converting, .validating: false
        case .queued, .succeeded, .succeededWithWarnings, .failed: true
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
