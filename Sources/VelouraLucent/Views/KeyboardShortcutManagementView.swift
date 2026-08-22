import AppKit
import SwiftUI

private enum KeyboardOperationTab: String, CaseIterable, Identifiable {
    case editable = "変更できるショートカット"
    case fixed = "固定の操作キー"

    var id: String { rawValue }
}

private struct FixedKeyboardOperation: Identifiable {
    let id: String
    let operation: String
    let keys: String
    let detail: String
}

@MainActor
struct KeyboardShortcutManagementView: View {
    @Bindable var settings: KeyboardShortcutSettings
    let processedAudioTitle: String
    let onDismiss: () -> Void

    @State private var selectedTab: KeyboardOperationTab = .editable
    @State private var editingAction: VelouraShortcutAction?
    @State private var validationMessage: String?

    private let completionButtonTint = Color(
        red: 92 / 255,
        green: 71 / 255,
        blue: 208 / 255
    )

    private let componentFixedOperations = [
        FixedKeyboardOperation(
            id: "knob",
            operation: "ロータリーノブ",
            keys: "↑  ↓  ←  →",
            detail: "ノブを選択して値を1段階ずつ調整"
        ),
        FixedKeyboardOperation(
            id: "waveform-pan",
            operation: "拡大中の波形",
            keys: "←  →",
            detail: "波形を選択して表示範囲を左右へ移動"
        ),
        FixedKeyboardOperation(
            id: "slider",
            operation: "スライダー",
            keys: "↑  ↓  ←  →",
            detail: "選択中の値を増減"
        ),
        FixedKeyboardOperation(
            id: "focus",
            operation: "ボタン・タブ・開閉項目",
            keys: "Tab  /  Space",
            detail: "Tabで移動し、Spaceで実行"
        ),
        FixedKeyboardOperation(
            id: "dialog",
            operation: "確認画面",
            keys: "Return  /  Esc",
            detail: "決定またはキャンセル"
        ),
        FixedKeyboardOperation(
            id: "voiceover-waveform",
            operation: "波形位置・波形の高さ",
            keys: "VoiceOverの増減操作",
            detail: "アクセシビリティ操作で位置や高さを調整"
        ),
    ]

    private var fixedOperations: [FixedKeyboardOperation] {
        KeyboardShortcutSettings.systemFixedOperations.map { operation in
            FixedKeyboardOperation(
                id: operation.id,
                operation: operation.operation,
                keys: operation.keys,
                detail: operation.detail
            )
        } + componentFixedOperations
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tabPicker
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 720, height: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .velouraAdaptiveGlass(in: .rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.18), radius: 30, y: 14)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("キーボード操作")
                .font(.title.bold())
            Text("ショートカットの変更と、固定操作キーの確認ができます")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    private var tabPicker: some View {
        LiquidGlassSegmentedPicker(
            title: "キーボード操作の種類",
            options: KeyboardOperationTab.allCases,
            selection: $selectedTab,
            label: \.rawValue
        )
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
        .onChange(of: selectedTab) {
            editingAction = nil
            validationMessage = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .editable:
            editableShortcutList
        case .fixed:
            fixedOperationList
        }
    }

    private var editableShortcutList: some View {
        VStack(spacing: 0) {
            columnHeader
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(VelouraShortcutCategory.allCases) { category in
                        Section {
                            ForEach(actions(in: category)) { action in
                                editableRow(action)
                                Divider().padding(.leading, 18)
                            }
                        } header: {
                            sectionHeader(category.rawValue)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .velouraTransientOverlayScrollIndicators()

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.07))
                    .accessibilityLabel("ショートカット設定エラー")
                    .accessibilityValue(validationMessage)
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Text("操作")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("ショートカット")
                .frame(width: 190, alignment: .leading)
            Color.clear.frame(width: 112, height: 1)
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }

    private func editableRow(_ action: VelouraShortcutAction) -> some View {
        let actionTitle = title(for: action)
        let isEditing = editingAction == action

        return HStack(spacing: 12) {
            Text(actionTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            shortcutCell(action)
                .frame(width: 190, alignment: .leading)

            HStack(spacing: 8) {
                Button {
                    editingAction = isEditing ? nil : action
                    validationMessage = nil
                } label: {
                    Image(systemName: isEditing ? "xmark" : "pencil")
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .velouraAdaptiveGlass(in: Circle(), interactive: true)
                .accessibilityLabel(
                    isEditing
                        ? "\(actionTitle)の変更をキャンセル"
                        : "\(actionTitle)のショートカットを変更"
                )
                .help(
                    isEditing
                        ? "ショートカットの変更をキャンセル"
                        : "ショートカットを設定・変更"
                )

                Button {
                    settings.removeShortcut(for: action)
                    if editingAction == action {
                        editingAction = nil
                    }
                    validationMessage = nil
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .velouraAdaptiveGlass(in: Circle(), interactive: true)
                .disabled(settings.shortcut(for: action) == nil)
                .accessibilityLabel("\(actionTitle)のショートカットを削除")
                .help("ショートカットを削除")

                Button {
                    if let conflict = settings.reset(action) {
                        let shortcutText = action.defaultShortcut?.displayText
                            ?? "初期ショートカット"
                        validationMessage = "\(shortcutText)は「\(title(for: conflict))」で使用されています。"
                        return
                    }
                    if editingAction == action {
                        editingAction = nil
                    }
                    validationMessage = nil
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .velouraAdaptiveGlass(in: Circle(), interactive: true)
                .disabled(settings.isUsingDefaultShortcut(for: action))
                .accessibilityLabel("\(actionTitle)のショートカットを初期設定へ戻す")
                .help("この操作だけ初期設定へ戻す")
            }
            .frame(width: 112)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 48)
    }

    @ViewBuilder
    private func shortcutCell(_ action: VelouraShortcutAction) -> some View {
        if editingAction == action {
            ZStack(alignment: .leading) {
                Text("キーを入力…")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.purple)
                ShortcutKeyCaptureView { shortcut in
                    accept(shortcut, for: action)
                }
                .frame(width: 1, height: 1)
                .opacity(0.01)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityLabel("\(title(for: action))のショートカット入力待ち")
        } else if let shortcut = settings.shortcut(for: action) {
            Text(shortcut.displayText)
                .font(.body.monospaced().weight(.semibold))
        } else {
            Text("未設定")
                .foregroundStyle(.tertiary)
        }
    }

    private var fixedOperationList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("操作")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("キー")
                    .frame(width: 230, alignment: .leading)
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(fixedOperations) { operation in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(operation.operation)
                                    .fontWeight(.medium)
                                Text(operation.detail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text(operation.keys)
                                .font(.body.monospaced().weight(.semibold))
                                .frame(width: 230, alignment: .leading)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        Divider().padding(.leading, 18)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .velouraTransientOverlayScrollIndicators()
        }
    }

    private var footer: some View {
        HStack {
            Button {
                settings.resetAll()
                editingAction = nil
                validationMessage = nil
            } label: {
                Text("すべて初期設定へ戻す")
                    .font(.callout.weight(.medium))
                    .frame(width: 128)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)

            Spacer()

            Button(action: onDismiss) {
                Text("完了")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 84)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(completionButtonTint)
            .keyboardShortcut(.defaultAction)

            Button("閉じる", action: onDismiss)
                .keyboardShortcut(.cancelAction)
                .hidden()
                .frame(width: 0, height: 0)
                .disabled(editingAction != nil)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
    }

    private func actions(in category: VelouraShortcutCategory) -> [VelouraShortcutAction] {
        VelouraShortcutAction.allCases.filter { $0.category == category }
    }

    private func accept(
        _ shortcut: VelouraShortcutConfiguration,
        for action: VelouraShortcutAction
    ) {
        guard shortcut.isAllowed else {
            validationMessage = "文字キー単独、Tab、およびReturn・矢印キー単独は設定できません。"
            return
        }
        if let fixedOperation = settings.fixedOperationConflict(for: shortcut) {
            validationMessage = "\(shortcut.displayText)はmacOS標準の「\(fixedOperation)」で使用されています。"
            return
        }
        if let conflict = settings.conflictingAction(for: shortcut, excluding: action) {
            validationMessage = "\(shortcut.displayText)は「\(title(for: conflict))」で使用されています。"
            return
        }

        settings.assign(shortcut, to: action)
        editingAction = nil
        validationMessage = nil
    }

    private func title(for action: VelouraShortcutAction) -> String {
        action.title(processedAudioTitle: processedAudioTitle)
    }
}

private struct ShortcutKeyCaptureView: NSViewRepresentable {
    let onRecord: (VelouraShortcutConfiguration) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRecord: onRecord)
    }

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onRecord = context.coordinator.onRecord
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        context.coordinator.onRecord = onRecord
        nsView.onRecord = context.coordinator.onRecord
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class Coordinator {
        var onRecord: (VelouraShortcutConfiguration) -> Void

        init(onRecord: @escaping (VelouraShortcutConfiguration) -> Void) {
            self.onRecord = onRecord
        }
    }
}

private final class KeyCaptureNSView: NSView {
    var onRecord: ((VelouraShortcutConfiguration) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            window?.makeFirstResponder(self)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        record(event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 {
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if modifiers.contains(.shift) {
                window?.selectPreviousKeyView(nil)
            } else {
                window?.selectNextKeyView(nil)
            }
            return
        }

        if !record(event) {
            super.keyDown(with: event)
        }
    }

    @discardableResult
    private func record(_ event: NSEvent) -> Bool {
        guard
            let characters = event.charactersIgnoringModifiers,
            let key = characters.first.map(String.init),
            !key.isEmpty
        else {
            return false
        }

        var modifiers: Set<VelouraShortcutModifier> = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }

        onRecord?(VelouraShortcutConfiguration(key: key, modifiers: modifiers))
        return true
    }
}
