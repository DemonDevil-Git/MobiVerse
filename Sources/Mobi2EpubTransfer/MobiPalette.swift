import AppKit
import SwiftUI

enum AppAppearancePreference: String, CaseIterable, Identifiable {
    static let storageKey = "MobiVerseAppAppearance"

    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L10n.string("System")
        case .light: L10n.string("Light")
        case .dark: L10n.string("Dark")
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }

    @MainActor
    func apply() {
        switch self {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// MobiVerse's warm editorial palette, resolved from the current macOS appearance.
/// Dark mode keeps the paper-and-ink character while meeting readable contrast.
enum MobiPalette {
    static let ink = adaptive(
        light: NSColor(red: 0.08, green: 0.16, blue: 0.20, alpha: 1),
        dark: NSColor(red: 0.91, green: 0.89, blue: 0.83, alpha: 1)
    )
    static let paper = adaptive(
        light: NSColor(red: 0.965, green: 0.948, blue: 0.91, alpha: 1),
        dark: NSColor(red: 0.065, green: 0.082, blue: 0.086, alpha: 1)
    )
    static let sidebar = adaptive(
        light: NSColor(red: 0.973, green: 0.961, blue: 0.933, alpha: 1),
        dark: NSColor(red: 0.09, green: 0.112, blue: 0.113, alpha: 1)
    )
    static let cream = adaptive(
        light: NSColor(red: 0.95, green: 0.90, blue: 0.81, alpha: 1),
        dark: NSColor(red: 0.20, green: 0.19, blue: 0.15, alpha: 1)
    )
    static let surface = adaptive(
        light: NSColor(red: 1, green: 0.995, blue: 0.975, alpha: 1),
        dark: NSColor(red: 0.125, green: 0.148, blue: 0.147, alpha: 1)
    )
    static let surfaceRaised = adaptive(
        light: NSColor.white,
        dark: NSColor(red: 0.165, green: 0.188, blue: 0.184, alpha: 1)
    )
    static let sage = adaptive(
        light: NSColor(red: 0.31, green: 0.48, blue: 0.31, alpha: 1),
        dark: NSColor(red: 0.55, green: 0.72, blue: 0.51, alpha: 1)
    )
    static let terracotta = adaptive(
        light: NSColor(red: 0.72, green: 0.28, blue: 0.16, alpha: 1),
        dark: NSColor(red: 0.91, green: 0.48, blue: 0.34, alpha: 1)
    )
    static let walnut = adaptive(
        light: NSColor(red: 0.38, green: 0.21, blue: 0.12, alpha: 1),
        dark: NSColor(red: 0.75, green: 0.59, blue: 0.44, alpha: 1)
    )
    static let walnutLight = adaptive(
        light: NSColor(red: 0.58, green: 0.36, blue: 0.22, alpha: 1),
        dark: NSColor(red: 0.84, green: 0.67, blue: 0.48, alpha: 1)
    )
    static let cobalt = adaptive(
        light: NSColor(red: 0.18, green: 0.35, blue: 0.45, alpha: 1),
        dark: NSColor(red: 0.45, green: 0.69, blue: 0.80, alpha: 1)
    )
    static let onAccent = Color.white
    static let mint = sage
    static let coral = terracotta

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}
