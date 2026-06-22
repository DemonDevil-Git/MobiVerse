import AppKit
import SwiftUI

struct OpenBookRequest: Equatable {
    let id = UUID()
    let urls: [URL]
}

@MainActor
final class OpenBookRouter: ObservableObject {
    static let shared = OpenBookRouter()

    @Published var request: OpenBookRequest?

    func open(_ urls: [URL]) {
        request = OpenBookRequest(urls: urls)
    }
}

final class MobiVerseAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            OpenBookRouter.shared.open(urls)
        }
    }
}

@main
struct Mobi2EpubTransferApp: App {
    @NSApplicationDelegateAdaptor(MobiVerseAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 920, minHeight: 620)
        }
        .windowStyle(.titleBar)
    }
}
