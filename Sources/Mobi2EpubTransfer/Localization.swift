import Foundation

enum AppLanguagePreference: String, CaseIterable, Identifiable {
    static let storageKey = "MobiVerseAppLanguage"

    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    /// Language names stay self-identifying so the selector remains usable
    /// even when the current interface language is unfamiliar.
    var title: String {
        switch self {
        case .system: "System Language"
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        }
    }

    var localizationIdentifier: String {
        switch self {
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return preferred.hasPrefix("zh") ? "zh-Hans" : "en"
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        }
    }

    static var selected: AppLanguagePreference {
        let stored = UserDefaults.standard.string(forKey: storageKey)
        return stored.flatMap(AppLanguagePreference.init(rawValue:)) ?? .simplifiedChinese
    }
}

enum L10n {
    static func string(_ key: String) -> String {
        let language = AppLanguagePreference.selected.localizationIdentifier
        guard language != "en" else { return key }

        for container in [Bundle.module, Bundle.main] {
            guard
                let path = container.path(forResource: language, ofType: "lproj"),
                let localizedBundle = Bundle(path: path)
            else { continue }
            let value = localizedBundle.localizedString(forKey: key, value: key, table: nil)
            if value != key { return value }
        }
        return key
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: AppLanguagePreference.selected.locale, arguments: arguments)
    }
}
