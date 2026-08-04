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
    @AppStorage(AppLanguagePreference.storageKey) private var languageRawValue = AppLanguagePreference.simplifiedChinese.rawValue

    private var selectedLanguage: AppLanguagePreference {
        AppLanguagePreference(rawValue: languageRawValue) ?? .simplifiedChinese
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1080, minHeight: 720)
                .environment(\.locale, selectedLanguage.locale)
        }
        .windowStyle(.titleBar)
    }
}
