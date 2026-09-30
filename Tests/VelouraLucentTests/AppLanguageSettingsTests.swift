import Foundation
import Testing
@testable import VelouraLucent

struct AppLanguageSettingsTests {
    @Test
    func threeLanguageChoicesResolveToSupportedLocales() {
        #expect(AppLanguageSelection.allCases == [.system, .japanese, .english])
        #expect(AppLanguageSettings.locale(for: AppLanguageSelection.japanese.rawValue).identifier == "ja")
        #expect(AppLanguageSettings.locale(for: AppLanguageSelection.english.rawValue).identifier == "en")
        #expect(["ja", "en"].contains(
            AppLanguageSettings.locale(for: AppLanguageSelection.system.rawValue).identifier
        ))
    }

    @Test
    func englishCatalogContainsTheLanguagePicker() throws {
        let bundle = try #require(AppResourceBundle.bundle)
        let english = bundle.localizedString(
            forKey: "システム設定に従う",
            value: nil,
            table: "Localizable",
            localizations: [Locale.Language(identifier: "en")]
        )
        #expect(english == "Follow System Settings")
    }
}
