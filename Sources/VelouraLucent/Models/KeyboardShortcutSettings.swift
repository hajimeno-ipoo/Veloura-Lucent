import Foundation
import SwiftUI

enum VelouraShortcutModifier: String, CaseIterable, Codable, Hashable {
    case control
    case option
    case shift
    case command

    var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }

    var eventModifier: EventModifiers {
        switch self {
        case .control: .control
        case .option: .option
        case .shift: .shift
        case .command: .command
        }
    }
}

struct VelouraShortcutConfiguration: Codable, Equatable, Hashable {
    let key: String
    let modifiers: Set<VelouraShortcutModifier>

    init(key: String, modifiers: Set<VelouraShortcutModifier> = []) {
        self.key = Self.normalizedKey(key)
        self.modifiers = modifiers
    }

    var keyboardShortcut: KeyboardShortcut? {
        guard key.count == 1, let character = key.first else { return nil }
        let eventModifiers = modifiers.reduce(into: EventModifiers()) { result, modifier in
            result.insert(modifier.eventModifier)
        }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: eventModifiers)
    }

    var displayText: String {
        let modifierText = VelouraShortcutModifier.allCases
            .filter(modifiers.contains)
            .map(\.symbol)
            .joined()
        return modifierText + keyDisplayText
    }

    var isAllowed: Bool {
        guard key.count == 1 else { return false }
        if Self.fixedKeysRegardlessOfModifiers.contains(key) {
            return false
        }
        if Self.fixedUnmodifiedKeys.contains(key), modifiers.isEmpty {
            return false
        }
        if Self.safeUnmodifiedKeys.contains(key) {
            return true
        }
        return !modifiers.isEmpty
    }

    private var keyDisplayText: String {
        switch key {
        case " ": "Space"
        case "\u{1B}": "Esc"
        case "\r", "\n": "Return"
        case "\t": "Tab"
        case "\u{7F}": "Delete"
        case "\u{F700}": "↑"
        case "\u{F701}": "↓"
        case "\u{F702}": "←"
        case "\u{F703}": "→"
        default:
            if let functionKeyNumber {
                "F\(functionKeyNumber)"
            } else {
                key.uppercased()
            }
        }
    }

    private var functionKeyNumber: Int? {
        guard let scalar = key.unicodeScalars.first, key.unicodeScalars.count == 1 else {
            return nil
        }
        let value = scalar.value
        let firstFunctionKey: UInt32 = 0xF704
        let lastFunctionKey: UInt32 = 0xF71B
        guard (firstFunctionKey ... lastFunctionKey).contains(value) else { return nil }
        return Int(value - firstFunctionKey + 1)
    }

    private static let fixedKeysRegardlessOfModifiers: Set<String> = ["\t"]

    private static let fixedUnmodifiedKeys: Set<String> = [
        "\r", "\n", "\u{F700}", "\u{F701}", "\u{F702}", "\u{F703}",
    ]

    private static let safeUnmodifiedKeys: Set<String> = [" ", "\u{1B}"]

    private static func normalizedKey(_ key: String) -> String {
        guard key.count == 1 else { return key }
        if key.range(of: "[A-Z]", options: .regularExpression) != nil {
            return key.lowercased()
        }
        return key
    }
}

enum VelouraShortcutCategory: String, CaseIterable, Identifiable {
    case file = "ファイル"
    case processing = "処理"
    case playback = "再生"
    case comparison = "比較対象"
    case mode = "モード"
    case centerDisplay = "中央表示"
    case waveform = "波形"
    case inspector = "右側設定"
    case analysis = "解析結果"
    case window = "ウインドウ"

    var id: String { rawValue }
}

struct VelouraFixedShortcut {
    let configuration: VelouraShortcutConfiguration
    let conflictTitle: String
}

struct VelouraFixedKeyboardOperation: Identifiable {
    let id: String
    let operation: String
    let shortcuts: [VelouraFixedShortcut]
    let detail: String

    var keys: String {
        shortcuts.map(\.configuration.displayText).joined(separator: "  ")
    }
}

enum VelouraShortcutAction: String, CaseIterable, Codable, Identifiable {
    case chooseInputAudio
    case openExportMenu
    case runCorrection
    case runRemix
    case runMastering
    case playSideA
    case togglePlayback
    case stopPlayback
    case playSideB
    case toggleComparisonSide
    case toggleLoudnessMatching
    case compareInputCorrected
    case compareInputMastered
    case compareCorrectedMastered
    case selectStandardMode
    case selectStemMode
    case showBasicDisplay
    case showDetailedAnalysis
    case showFullLog
    case zoomWaveformOut
    case zoomWaveformIn
    case showWholeWaveform
    case showCorrectionSettings
    case showRemixSettings
    case showMasteringSettings
    case showAppSettings
    case showInputAnalysis
    case showCorrectedAnalysis
    case showMasteredAnalysis
    case showCompletionReport
    case toggleSidebar
    case toggleInspector

    var id: String { rawValue }

    var title: String {
        title(processedAudioTitle: "補正後")
    }

    func title(processedAudioTitle: String) -> String {
        switch self {
        case .chooseInputAudio: "音声を選ぶ"
        case .openExportMenu: "書き出しメニュー"
        case .runCorrection: "補正を実行／キャンセル"
        case .runRemix: "再ミックスを実行／キャンセル"
        case .runMastering: "マスタリングを実行／キャンセル"
        case .playSideA: "Aを再生"
        case .togglePlayback: "再生・一時停止"
        case .stopPlayback: "停止"
        case .playSideB: "Bを再生"
        case .toggleComparisonSide: "A/B切替"
        case .toggleLoudnessMatching: "ラウドネス合わせ"
        case .compareInputCorrected: "入力と\(processedAudioTitle)を比較"
        case .compareInputMastered: "入力と最終版を比較"
        case .compareCorrectedMastered: "\(processedAudioTitle)と最終版を比較"
        case .selectStandardMode: "通常補正"
        case .selectStemMode: "Stem Mode"
        case .showBasicDisplay: "基本表示"
        case .showDetailedAnalysis: "詳細解析"
        case .showFullLog: "詳細ログ"
        case .zoomWaveformOut: "選択中の波形を縮小"
        case .zoomWaveformIn: "選択中の波形を拡大"
        case .showWholeWaveform: "選択中の波形を全体表示"
        case .showCorrectionSettings: "補正設定"
        case .showRemixSettings: "再ミックス設定"
        case .showMasteringSettings: "マスタリング設定"
        case .showAppSettings: "アプリ設定"
        case .showInputAnalysis: "入力の解析結果"
        case .showCorrectedAnalysis: "\(processedAudioTitle)の解析結果"
        case .showMasteredAnalysis: "最終版の解析結果"
        case .showCompletionReport: "完了後レポート"
        case .toggleSidebar: "サイドバーを表示／非表示"
        case .toggleInspector: "右側設定を表示／非表示"
        }
    }

    var category: VelouraShortcutCategory {
        switch self {
        case .chooseInputAudio, .openExportMenu: .file
        case .runCorrection, .runRemix, .runMastering: .processing
        case .playSideA, .togglePlayback, .stopPlayback, .playSideB,
             .toggleComparisonSide, .toggleLoudnessMatching: .playback
        case .compareInputCorrected, .compareInputMastered,
             .compareCorrectedMastered: .comparison
        case .selectStandardMode, .selectStemMode: .mode
        case .showBasicDisplay, .showDetailedAnalysis, .showFullLog: .centerDisplay
        case .zoomWaveformOut, .zoomWaveformIn, .showWholeWaveform: .waveform
        case .showCorrectionSettings, .showRemixSettings,
             .showMasteringSettings, .showAppSettings: .inspector
        case .showInputAnalysis, .showCorrectedAnalysis,
             .showMasteredAnalysis, .showCompletionReport: .analysis
        case .toggleSidebar, .toggleInspector: .window
        }
    }

    var defaultShortcut: VelouraShortcutConfiguration? {
        switch self {
        case .chooseInputAudio:
            VelouraShortcutConfiguration(key: "o", modifiers: [.command])
        case .runCorrection:
            VelouraShortcutConfiguration(key: "r", modifiers: [.command])
        case .runRemix:
            VelouraShortcutConfiguration(key: "r", modifiers: [.command, .option])
        case .runMastering:
            VelouraShortcutConfiguration(key: "r", modifiers: [.command, .shift])
        case .togglePlayback:
            VelouraShortcutConfiguration(key: " ")
        case .stopPlayback:
            VelouraShortcutConfiguration(key: "\u{1B}")
        case .toggleComparisonSide:
            VelouraShortcutConfiguration(key: "b", modifiers: [.command])
        case .toggleSidebar:
            VelouraShortcutConfiguration(key: "s", modifiers: [.command, .control])
        case .toggleInspector:
            VelouraShortcutConfiguration(key: "i", modifiers: [.command, .option])
        default:
            nil
        }
    }
}

@MainActor
@Observable
final class KeyboardShortcutSettings {
    static let shared = KeyboardShortcutSettings()
    static let storageKey = "veloura.keyboardShortcutAssignments.v1"
    static let systemFixedOperations = [
        VelouraFixedKeyboardOperation(
            id: "app",
            operation: "アプリ",
            shortcuts: [
                fixedShortcut("q", modifiers: [.command], title: "アプリを終了"),
                fixedShortcut("h", modifiers: [.command], title: "アプリを隠す"),
                fixedShortcut("h", modifiers: [.command, .option], title: "ほかを隠す"),
            ],
            detail: "終了、隠す、ほかを隠す"
        ),
        VelouraFixedKeyboardOperation(
            id: "window",
            operation: "ウインドウ",
            shortcuts: [
                fixedShortcut("n", modifiers: [.command], title: "新規ウインドウ"),
                fixedShortcut("w", modifiers: [.command], title: "ウインドウを閉じる"),
                fixedShortcut("m", modifiers: [.command], title: "ウインドウをしまう"),
                fixedShortcut(
                    "f",
                    modifiers: [.command, .control],
                    title: "フルスクリーン"
                ),
            ],
            detail: "新規、閉じる、しまう、フルスクリーン"
        ),
        VelouraFixedKeyboardOperation(
            id: "text-editing",
            operation: "文字入力",
            shortcuts: [
                fixedShortcut("x", modifiers: [.command], title: "カット"),
                fixedShortcut("c", modifiers: [.command], title: "コピー"),
                fixedShortcut("v", modifiers: [.command], title: "ペースト"),
                fixedShortcut("a", modifiers: [.command], title: "すべて選択"),
                fixedShortcut("z", modifiers: [.command], title: "取り消す"),
                fixedShortcut("z", modifiers: [.command, .shift], title: "やり直す"),
            ],
            detail: "入力欄でカット、コピー、ペースト、全選択、取り消し、やり直し"
        ),
    ]

    private enum Assignment: Equatable {
        case assigned(VelouraShortcutConfiguration)
        case unassigned
    }

    private struct StoredAssignment: Codable {
        let action: String
        let shortcut: VelouraShortcutConfiguration?
    }

    private var assignments: [VelouraShortcutAction: Assignment]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        assignments = Dictionary(uniqueKeysWithValues: VelouraShortcutAction.allCases.map {
            ($0, $0.defaultShortcut.map(Assignment.assigned) ?? .unassigned)
        })
        load()
    }

    func shortcut(for action: VelouraShortcutAction) -> VelouraShortcutConfiguration? {
        guard case let .assigned(shortcut) = assignments[action] else { return nil }
        return shortcut
    }

    func keyboardShortcut(for action: VelouraShortcutAction) -> KeyboardShortcut? {
        shortcut(for: action)?.keyboardShortcut
    }

    func isUsingDefaultShortcut(for action: VelouraShortcutAction) -> Bool {
        shortcut(for: action) == action.defaultShortcut
    }

    func conflictingAction(
        for shortcut: VelouraShortcutConfiguration,
        excluding action: VelouraShortcutAction
    ) -> VelouraShortcutAction? {
        VelouraShortcutAction.allCases.first { candidate in
            candidate != action && self.shortcut(for: candidate) == shortcut
        }
    }

    func fixedOperationConflict(for shortcut: VelouraShortcutConfiguration) -> String? {
        Self.fixedOperationShortcuts[shortcut]
    }

    func assign(_ shortcut: VelouraShortcutConfiguration, to action: VelouraShortcutAction) {
        assignments[action] = .assigned(shortcut)
        save()
    }

    func removeShortcut(for action: VelouraShortcutAction) {
        assignments[action] = .unassigned
        save()
    }

    @discardableResult
    func reset(_ action: VelouraShortcutAction) -> VelouraShortcutAction? {
        if let defaultShortcut = action.defaultShortcut,
           let conflict = conflictingAction(for: defaultShortcut, excluding: action) {
            return conflict
        }
        assignments[action] = action.defaultShortcut.map(Assignment.assigned) ?? .unassigned
        save()
        return nil
    }

    func resetAll() {
        assignments = Dictionary(uniqueKeysWithValues: VelouraShortcutAction.allCases.map {
            ($0, $0.defaultShortcut.map(Assignment.assigned) ?? .unassigned)
        })
        save()
    }

    private func load() {
        guard
            let data = defaults.data(forKey: Self.storageKey),
            let storedAssignments = try? JSONDecoder().decode([StoredAssignment].self, from: data)
        else {
            return
        }

        for stored in storedAssignments {
            guard let action = VelouraShortcutAction(rawValue: stored.action) else { continue }
            assignments[action] = stored.shortcut.map(Assignment.assigned) ?? .unassigned
        }
    }

    private func save() {
        let storedAssignments = VelouraShortcutAction.allCases.map { action in
            StoredAssignment(action: action.rawValue, shortcut: shortcut(for: action))
        }
        guard let data = try? JSONEncoder().encode(storedAssignments) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static let fixedOperationShortcuts = Dictionary(
        uniqueKeysWithValues: systemFixedOperations.flatMap { operation in
            operation.shortcuts.map { shortcut in
                (shortcut.configuration, shortcut.conflictTitle)
            }
        }
    )

    private static func fixedShortcut(
        _ key: String,
        modifiers: Set<VelouraShortcutModifier>,
        title: String
    ) -> VelouraFixedShortcut {
        VelouraFixedShortcut(
            configuration: VelouraShortcutConfiguration(
                key: key,
                modifiers: modifiers
            ),
            conflictTitle: title
        )
    }
}
