import Foundation

enum AppLanguageSelection: String, CaseIterable, Sendable {
    case system
    case japanese = "ja"
    case english = "en"
}

enum AppLanguageSettings {
    static let key = "appLanguageSelection"

    static var selection: AppLanguageSelection {
        AppLanguageSelection(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }

    static var locale: Locale {
        locale(for: selection.rawValue)
    }

    static func locale(for rawValue: String) -> Locale {
        Locale(identifier: languageCode(for: rawValue))
    }

    static func string(_ key: String) -> String {
        let language = languageCode(for: selection.rawValue)
        return localizedBundles[language]?.localizedString(
            forKey: key, value: key, table: "Localizable"
        ) ?? key
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }

    private static let resourceBundle: Bundle = {
        Bundle.main.bundleURL.pathExtension == "app" ? .main : (AppResourceBundle.bundle ?? .main)
    }()

    private static let localizedBundles: [String: Bundle] = {
        Dictionary(uniqueKeysWithValues: ["ja", "en"].compactMap { language in
            guard let path = resourceBundle.path(forResource: language, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { return nil }
            return (language, bundle)
        })
    }()

    private static let systemLanguage: String = {
        resourceBundle.preferredLocalizations.first { localization in
            localization == "ja" || localization.hasPrefix("ja-") ||
                localization == "en" || localization.hasPrefix("en-")
        }
        .map { $0.hasPrefix("en") ? "en" : "ja" } ?? "ja"
    }()

    private static func languageCode(for rawValue: String) -> String {
        switch AppLanguageSelection(rawValue: rawValue) ?? .system {
        case .japanese:
            "ja"
        case .english:
            "en"
        case .system:
            systemLanguage
        }
    }
}
