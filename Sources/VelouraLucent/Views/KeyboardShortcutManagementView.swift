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
}

private struct FixedKeyboardOperationGroup: Identifiable {
    let id: String
    let title: String
    let operations: [FixedKeyboardOperation]
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

    private let componentFixedOperationGroups = [
        FixedKeyboardOperationGroup(
            id: "knob",
            title: "ロータリーノブ",
            operations: [
                FixedKeyboardOperation(
                    id: "knob-step",
                    operation: "値を1段階ずつ調整",
                    keys: "↑  ↓  ←  →"
                ),
            ]
        ),
        FixedKeyboardOperationGroup(
            id: "waveform-pan",
            title: "拡大中の波形",
            operations: [
                FixedKeyboardOperation(
                    id: "waveform-pan-horizontal",
                    operation: "表示範囲を左右へ移動",
                    keys: "←  →"
                ),
            ]
        ),
        FixedKeyboardOperationGroup(
            id: "slider",
            title: "スライダー",
            operations: [
                FixedKeyboardOperation(
                    id: "slider-step",
                    operation: "選択中の値を増減",
                    keys: "↑  ↓  ←  →"
                ),
            ]
        ),
        FixedKeyboardOperationGroup(
            id: "focus",
            title: "ボタン・タブ・開閉項目",
            operations: [
                FixedKeyboardOperation(
                    id: "focus-move",
                    operation: "次の操作へ移動",
                    keys: "Tab"
                ),
                FixedKeyboardOperation(
                    id: "focus-activate",
                    operation: "選択中の操作を実行",
                    keys: "Space"
                ),
            ]
        ),
        FixedKeyboardOperationGroup(
            id: "dialog",
            title: "確認画面",
            operations: [
                FixedKeyboardOperation(
                    id: "dialog-confirm",
                    operation: "確認画面で決定",
                    keys: "Return"
                ),
                FixedKeyboardOperation(
                    id: "dialog-cancel",
                    operation: "確認画面をキャンセル",
                    keys: "Esc"
                ),
            ]
        ),
        FixedKeyboardOperationGroup(
            id: "voiceover",
            title: "VoiceOver",
            operations: [
                FixedKeyboardOperation(
                    id: "voiceover-waveform",
                    operation: "波形位置・波形の高さを調整",
                    keys: "VoiceOverの増減操作"
                ),
            ]
        ),
    ]

    private var fixedOperationGroups: [FixedKeyboardOperationGroup] {
        KeyboardShortcutSettings.systemFixedOperations.map { group in
            FixedKeyboardOperationGroup(
                id: group.id,
                title: group.operation,
                operations: group.shortcuts.map { shortcut in
                    FixedKeyboardOperation(
                        id: "\(group.id)-\(shortcut.conflictTitle)",
                        operation: shortcut.conflictTitle,
                        keys: shortcut.configuration.displayText
                    )
                }
            )
        } + componentFixedOperationGroups
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
                .font(.title)
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
                            let categoryActions = actions(in: category)

                            shortcutCategoryCard {
                                ForEach(categoryActions) { action in
                                    editableRow(action)

                                    if action.id != categoryActions.last?.id {
                                        Divider().padding(.leading, 8)
                                    }
                                }
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
                    .font(.title3)
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
                .frame(width: 220, alignment: .leading)
            Color.clear.frame(width: 164, height: 1)
        }
        .font(.title3)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }

    private func editableRow(_ action: VelouraShortcutAction) -> some View {
        let actionTitle = title(for: action)
        let isEditing = editingAction == action

        return HStack(spacing: 12) {
            Text(actionTitle)
                .font(.system(size: 16, weight: .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            shortcutCell(action)
                .frame(width: 220, alignment: .leading)

            if isEditing {
                Color.clear.frame(width: 164, height: 1)
            } else {
                HStack(spacing: 8) {
                    Button {
                        editingAction = action
                        validationMessage = nil
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 20, weight: .regular))
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .velouraAdaptiveGlass(in: Circle(), interactive: true)
                    .accessibilityLabel("\(actionTitle)のショートカットを変更")
                    .help("ショートカットを設定・変更")

                    Button {
                        settings.removeShortcut(for: action)
                        validationMessage = nil
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 18, weight: .regular))
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
                        validationMessage = nil
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .regular))
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .velouraAdaptiveGlass(in: Circle(), interactive: true)
                    .disabled(settings.isUsingDefaultShortcut(for: action))
                    .accessibilityLabel("\(actionTitle)のショートカットを初期設定へ戻す")
                    .help("この操作だけ初期設定へ戻す")
                }
                .frame(width: 164)
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 52)
    }

    @ViewBuilder
    private func shortcutCell(_ action: VelouraShortcutAction) -> some View {
        if editingAction == action {
            HStack(spacing: 14) {
                ZStack(alignment: .leading) {
                    Text("キーを押してください")
                        .font(.title3)
                        .foregroundStyle(.purple)
                    ShortcutKeyCaptureView { shortcut in
                        accept(shortcut, for: action)
                    }
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                .accessibilityLabel("\(title(for: action))のショートカット入力待ち")

                Button {
                    editingAction = nil
                    validationMessage = nil
                } label: {
                    Text("キャンセル")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .frame(height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title(for: action))の変更をキャンセル")
                .help("ショートカットの変更をキャンセル")
            }
        } else if let shortcut = settings.shortcut(for: action) {
            Text(shortcut.displayText)
                .font(.system(size: 20, weight: .regular))
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
                    .frame(width: 260, alignment: .leading)
            }
            .font(.title3)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)

            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(fixedOperationGroups) { group in
                        Section {
                            shortcutCategoryCard {
                                ForEach(group.operations) { operation in
                                    HStack(spacing: 12) {
                                        Text(operation.operation)
                                            .font(.system(size: 16, weight: .regular))
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        Text(operation.keys)
                                            .font(.system(size: 20, weight: .regular))
                                            .frame(width: 260, alignment: .leading)
                                    }
                                    .padding(.horizontal, 8)
                                    .frame(minHeight: 52)

                                    if operation.id != group.operations.last?.id {
                                        Divider().padding(.leading, 8)
                                    }
                                }
                            }
                        } header: {
                            sectionHeader(group.title)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .velouraTransientOverlayScrollIndicators()
        }
    }

    private func shortcutCategoryCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.36), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack {
            Button {
                settings.resetAll()
                editingAction = nil
                validationMessage = nil
            } label: {
                Text("すべて初期設定へ戻す")
                    .font(.callout)
                    .frame(width: 128)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)

            Spacer()

            Button(action: onDismiss) {
                Text("完了")
                    .font(.callout)
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
            .font(.title3.bold())
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
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
