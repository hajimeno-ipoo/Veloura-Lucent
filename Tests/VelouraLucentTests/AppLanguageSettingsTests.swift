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

    @Test
    func processingModeNamesResolveInBothLanguages() throws {
        let bundle = try #require(AppResourceBundle.bundle)
        let names: [(String, String, String)] = [
            (ProcessingMode.standard.title, "スタンダード", "Standard"),
            (ProcessingMode.stem.title, "ステム", "Stem"),
            ("スタンダード補正", "スタンダード補正", "Standard correction"),
            ("ステム再ミックス", "ステム再ミックス", "Stem remix"),
            ("Veloura Lucent — ステム", "Veloura Lucent — ステム", "Veloura Lucent — Stem"),
            ("スタンダードとステムを切り替えます", "スタンダードとステムを切り替えます", "Switch between Standard and Stem."),
        ]
        for (source, japanese, english) in names {
            for (language, expected) in [("ja", japanese), ("en", english)] {
                #expect(bundle.localizedString(
                    forKey: source,
                    value: nil,
                    table: "Localizable",
                    localizations: [Locale.Language(identifier: language)]
                ) == expected)
            }
        }
    }

    @Test
    func comparisonSummariesResolveInBothLanguages() throws {
        let bundle = try #require(AppResourceBundle.bundle)
        let summaries: [(String, String, String)] = [
            (AudioComparisonPair.inputVsCorrected.summary, "入力と補正後を聴き比べます", "Compare the input with the corrected audio."),
            (AudioComparisonPair.inputVsMastered.summary, "入力と最終版を聴き比べます", "Compare the input with the final version."),
            (AudioComparisonPair.correctedVsMastered.summary, "補正後と最終版を聴き比べます", "Compare the corrected audio with the final version."),
            ("分離直後（raw）と補正後Stemを聴き比べます", "分離直後（raw）と補正後Stemを聴き比べます", "Compare the raw stem with the corrected stem."),
            ("補正後と再ミックスを聴き比べます", "補正後と再ミックスを聴き比べます", "Compare the corrected audio with the remix."),
        ]
        for (source, japanese, english) in summaries {
            for (language, expected) in [("ja", japanese), ("en", english)] {
                #expect(bundle.localizedString(
                    forKey: source,
                    value: nil,
                    table: "Localizable",
                    localizations: [Locale.Language(identifier: language)]
                ) == expected)
            }
        }
    }

    @Test
    func oversamplingLogCatalogContainsBothLanguages() throws {
        let bundle = try #require(AppResourceBundle.bundle)
        let lines = [
            ("高域修復/Oversampling: 4倍処理を適用", "High frequency repair/Oversampling: 4x oversampling applied"),
            ("倍音/Oversampling: 4倍処理を適用", "Harmonics/Oversampling: 4x oversampling applied"),
            ("空気感/Oversampling: 4倍処理を適用", "Air/Oversampling: 4x oversampling applied"),
        ]
        for (source, english) in lines {
            for (language, expected) in [("ja", source), ("en", english)] {
                #expect(bundle.localizedString(
                    forKey: source,
                    value: nil,
                    table: "Localizable",
                    localizations: [Locale.Language(identifier: language)]
                ) == expected)
            }
        }
    }
}
