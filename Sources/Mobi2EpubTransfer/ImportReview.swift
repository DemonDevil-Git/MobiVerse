import AppKit
import Foundation
import Mobi2EpubTransferCore
import SwiftUI

struct ReviewedImport: Sendable {
    let url: URL
    let source: ImportSource
    let detectedKind: BookContentKind
    let profile: ConversionProfile
    let readingDirection: EpubReadingDirection
}

struct PendingImport: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let source: ImportSource
    let classification: ClassificationResult
    var selectedProfile: ConversionProfile?
    var readingDirection: EpubReadingDirection

    init(url: URL, source: ImportSource, classification: ClassificationResult) {
        id = UUID()
        self.url = url
        self.source = source
        self.classification = classification
        selectedProfile = switch classification.kind {
        case .text: .textReflow
        case .comic: .comicFixedLayout
        case .uncertain: nil
        }
        readingDirection = .rightToLeft
    }

    var isEPUB: Bool { url.pathExtension.lowercased() == "epub" }
    var isReady: Bool { isEPUB || selectedProfile != nil }
}

@MainActor
final class ImportReviewCoordinator: ObservableObject {
    @Published var items: [PendingImport] = []
    @Published var isAnalyzing = false
    @Published var errorMessage: String?

    private let storeURL: URL

    init(storeURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.storeURL = storeURL ?? base
            .appendingPathComponent("MobiVerse", isDirectory: true)
            .appendingPathComponent("pending-imports.json")
        restore()
    }

    func analyze(
        urls: [URL],
        source: ImportSource,
        ebookConvertURL: URL?
    ) async {
        let unique = urls.filter { url in !items.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) }
        guard !unique.isEmpty else { return }
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }
        for url in unique {
            do {
                let result = try await BookClassifier(ebookConvertURL: ebookConvertURL).classify(url: url)
                items.append(PendingImport(url: url, source: source, classification: result))
                persist()
            } catch let error as ConversionServiceError {
                errorMessage = error.message
            } catch {
                let fallback = ClassificationResult(
                    kind: .uncertain,
                    confidence: 0,
                    evidence: "The file could not be classified: \(error.localizedDescription)"
                )
                items.append(PendingImport(url: url, source: source, classification: fallback))
                persist()
            }
        }
    }

    func binding(for item: PendingImport) -> Binding<PendingImport> {
        let id = item.id
        return Binding {
            self.items.first(where: { $0.id == id }) ?? item
        } set: { value in
            guard let index = self.items.firstIndex(where: { $0.id == id }) else { return }
            self.items[index] = value
            self.persist()
        }
    }

    func removeAll() {
        items.removeAll()
        persist()
    }

    private func restore() {
        guard let data = try? Data(contentsOf: storeURL),
              let restored = try? JSONDecoder().decode([PendingImport].self, from: data) else { return }
        items = restored.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: storeURL, options: .atomic)
        } catch { }
    }
}

struct ImportReviewSheet: View {
    @ObservedObject var coordinator: ImportReviewCoordinator
    let onCancel: () -> Void
    let onConfirm: ([PendingImport]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review imported books")
                        .font(.system(size: 25, weight: .semibold, design: .serif))
                    Text("MobiVerse analyzed each file locally. Confirm the reading layout before continuing.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ProgressView().opacity(coordinator.isAnalyzing ? 1 : 0)
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(coordinator.items) { item in
                        ImportReviewRow(item: coordinator.binding(for: item))
                    }
                }
            }

            HStack {
                Text("No book content leaves this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Add to shelf") { onConfirm(coordinator.items) }
                    .buttonStyle(.borderedProminent)
                    .tint(MobiPalette.sage)
                    .disabled(coordinator.isAnalyzing || coordinator.items.isEmpty || !coordinator.items.allSatisfy(\.isReady))
            }
        }
        .padding(24)
        .frame(minWidth: 720, idealWidth: 820, minHeight: 480, idealHeight: 600)
        .foregroundStyle(MobiPalette.ink)
        .background(MobiPalette.paper)
    }
}

private struct ImportReviewRow: View {
    @Binding var item: PendingImport

    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 12)
                .fill(MobiPalette.ink.opacity(0.08))
                .frame(width: 58, height: 76)
                .overlay(Image(systemName: item.isEPUB ? "book.closed.fill" : "doc.richtext.fill").font(.title2))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.url.deletingPathExtension().lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Text(L10n.string(item.classification.evidence))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(confidenceLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.classification.kind == .uncertain ? .orange : .secondary)
            }
            Spacer()
            if item.isEPUB {
                Label("Ready to read", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Picker("Layout", selection: profileBinding) {
                    Text("Choose layout…").tag(ConversionProfile?.none)
                    Text("Text · Reflowable").tag(ConversionProfile?.some(.textReflow))
                    Text("Comic · Fixed layout").tag(ConversionProfile?.some(.comicFixedLayout))
                }
                .frame(width: 190)
                if item.selectedProfile == .comicFixedLayout {
                    Picker("Direction", selection: $item.readingDirection) {
                        Text("Right to left").tag(EpubReadingDirection.rightToLeft)
                        Text("Left to right").tag(EpubReadingDirection.leftToRight)
                    }
                    .frame(width: 145)
                }
            }
        }
        .padding(14)
        .background(MobiPalette.surface.opacity(0.84), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(MobiPalette.ink.opacity(0.08), lineWidth: 1)
        }
    }

    private var profileBinding: Binding<ConversionProfile?> {
        Binding(get: { item.selectedProfile }, set: { item.selectedProfile = $0 })
    }

    private var confidenceLabel: String {
        let percent = Int((item.classification.confidence * 100).rounded())
        let kind = switch item.classification.kind {
        case .text: L10n.string("Text book")
        case .comic: L10n.string("Comic / image book")
        case .uncertain: L10n.string("Needs your choice")
        }
        return L10n.format("%@ · %lld%% confidence", kind, percent)
    }
}
