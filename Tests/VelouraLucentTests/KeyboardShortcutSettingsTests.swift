import Foundation
import Testing
@testable import VelouraLucent

@MainActor
struct KeyboardShortcutSettingsTests {
    @Test("既存ショートカットを初期値として読み込む")
    func loadsExistingDefaults() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let settings = KeyboardShortcutSettings(defaults: defaults)

        #expect(settings.shortcut(for: .chooseInputAudio)?.displayText == "⌘O")
        #expect(settings.shortcut(for: .runRemix)?.displayText == "⌥⌘R")
        #expect(settings.shortcut(for: .togglePlayback)?.displayText == "Space")
        #expect(settings.shortcut(for: .stopPlayback)?.displayText == "Esc")
        #expect(settings.shortcut(for: .showDetailedAnalysis) == nil)
    }

    @Test("変更と削除を保存して次回起動時に復元する")
    func persistsAssignmentAndRemoval() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let first = KeyboardShortcutSettings(defaults: defaults)
        let shortcut = VelouraShortcutConfiguration(
            key: "d",
            modifiers: [.command, .shift]
        )

        first.assign(shortcut, to: .showDetailedAnalysis)
        first.removeShortcut(for: .chooseInputAudio)

        let restored = KeyboardShortcutSettings(defaults: defaults)
        #expect(restored.shortcut(for: .showDetailedAnalysis) == shortcut)
        #expect(restored.shortcut(for: .chooseInputAudio) == nil)
    }

    @Test("削除済み操作を含む保存データから有効な設定だけを復元する")
    func ignoresRemovedActionsWhenLoading() throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let storedJSON = """
        [
          {"action":"chooseInputAudio","shortcut":null},
          {"action":"previousPreviewStem","shortcut":null}
        ]
        """
        defaults.set(
            Data(storedJSON.utf8),
            forKey: KeyboardShortcutSettings.storageKey
        )

        let settings = KeyboardShortcutSettings(defaults: defaults)

        #expect(settings.shortcut(for: .chooseInputAudio) == nil)
        #expect(settings.shortcut(for: .runCorrection)?.displayText == "⌘R")
    }

    @Test("重複割り当てを検出して既存設定を示す")
    func findsConflictingAction() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let settings = KeyboardShortcutSettings(defaults: defaults)
        let shortcut = VelouraShortcutConfiguration(key: "r", modifiers: [.command])

        #expect(
            settings.conflictingAction(
                for: shortcut,
                excluding: .showDetailedAnalysis
            ) == .runCorrection
        )
        #expect(
            settings.conflictingAction(
                for: shortcut,
                excluding: .runCorrection
            ) == nil
        )
    }

    @Test("macOS標準の固定ショートカットとの重複を検出する")
    func findsFixedOperationConflict() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let settings = KeyboardShortcutSettings(defaults: defaults)

        #expect(
            settings.fixedOperationConflict(
                for: VelouraShortcutConfiguration(key: "q", modifiers: [.command])
            ) == "アプリを終了"
        )
        #expect(
            settings.fixedOperationConflict(
                for: VelouraShortcutConfiguration(key: "n", modifiers: [.command])
            ) == "新規ウインドウ"
        )
        #expect(
            KeyboardShortcutSettings.systemFixedOperations
                .flatMap(\.shortcuts)
                .contains {
                    $0.configuration
                        == VelouraShortcutConfiguration(
                            key: "z",
                            modifiers: [.command, .shift]
                        )
                }
        )
        #expect(
            settings.fixedOperationConflict(
                for: VelouraShortcutConfiguration(key: "o", modifiers: [.command])
            ) == nil
        )
    }

    @Test("全初期化で削除と追加を既定状態へ戻す")
    func resetAllRestoresDefaults() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let settings = KeyboardShortcutSettings(defaults: defaults)
        settings.removeShortcut(for: .runCorrection)
        settings.assign(
            VelouraShortcutConfiguration(key: "d", modifiers: [.command]),
            to: .showDetailedAnalysis
        )

        settings.resetAll()

        #expect(settings.shortcut(for: .runCorrection)?.displayText == "⌘R")
        #expect(settings.shortcut(for: .showDetailedAnalysis) == nil)
        #expect(settings.isUsingDefaultShortcut(for: .runCorrection))
        #expect(settings.isUsingDefaultShortcut(for: .showDetailedAnalysis))
    }

    @Test("項目別初期化でその操作だけを既定状態へ戻す")
    func resetOneActionRestoresOnlyItsDefault() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let settings = KeyboardShortcutSettings(defaults: defaults)
        settings.removeShortcut(for: .chooseInputAudio)
        settings.assign(
            VelouraShortcutConfiguration(key: "d", modifiers: [.command]),
            to: .showDetailedAnalysis
        )

        settings.reset(.chooseInputAudio)

        #expect(settings.shortcut(for: .chooseInputAudio)?.displayText == "⌘O")
        #expect(settings.shortcut(for: .showDetailedAnalysis)?.displayText == "⌘D")
    }

    @Test("項目別初期化で既定キーが使用中なら重複を作らない")
    func resetOneActionRejectsOccupiedDefault() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let settings = KeyboardShortcutSettings(defaults: defaults)
        let defaultShortcut = VelouraShortcutConfiguration(key: "o", modifiers: [.command])
        settings.removeShortcut(for: .chooseInputAudio)
        settings.assign(defaultShortcut, to: .showDetailedAnalysis)

        let conflict = settings.reset(.chooseInputAudio)

        #expect(conflict == .showDetailedAnalysis)
        #expect(settings.shortcut(for: .chooseInputAudio) == nil)
        #expect(settings.shortcut(for: .showDetailedAnalysis) == defaultShortcut)
    }

    @Test("固定操作キー単独と文字キー単独を割り当て対象外にする")
    func rejectsUnmodifiedFixedAndCharacterKeys() {
        #expect(!VelouraShortcutConfiguration(key: "a").isAllowed)
        #expect(!VelouraShortcutConfiguration(key: "\t").isAllowed)
        #expect(!VelouraShortcutConfiguration(key: "\t", modifiers: [.shift]).isAllowed)
        #expect(!VelouraShortcutConfiguration(key: "\u{F702}").isAllowed)
        #expect(VelouraShortcutConfiguration(key: " ").isAllowed)
        #expect(VelouraShortcutConfiguration(key: "\u{1B}").isAllowed)
        #expect(
            VelouraShortcutConfiguration(key: "a", modifiers: [.command]).isAllowed
        )
    }

    @Test("Stem再ミックス後は比較対象と解析結果の表示名を切り替える")
    func usesCurrentProcessedAudioTitle() {
        #expect(
            VelouraShortcutAction.compareInputCorrected.title(
                processedAudioTitle: "Stem再ミックス"
            ) == "入力とStem再ミックスを比較"
        )
        #expect(
            VelouraShortcutAction.compareCorrectedMastered.title(
                processedAudioTitle: "Stem再ミックス"
            ) == "Stem再ミックスと最終版を比較"
        )
        #expect(
            VelouraShortcutAction.showCorrectedAnalysis.title(
                processedAudioTitle: "Stem再ミックス"
            ) == "Stem再ミックスの解析結果"
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "KeyboardShortcutSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func clear(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: KeyboardShortcutSettings.storageKey)
    }
}
