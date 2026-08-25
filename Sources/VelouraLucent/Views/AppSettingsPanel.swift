import AppKit
import SwiftUI

struct AppSettingsPanel: View {
    private let preferences: CompletionNotificationPreferenceProviding
    private let notificationReporter: CompletionNotificationReporting
    @Binding private var windowBackgroundMaterialAmount: Double
    @Binding private var isWindowBackgroundBlurEnabled: Bool
    @Binding private var windowBackgroundBlurLevel: WindowBackgroundBlurLevel
    private let isWindowFullScreen: Bool
    private let openKeyboardShortcutManager: @MainActor () -> Void
    @State private var completionNotificationsEnabled: Bool
    @State private var completionNotificationItemStates: [CompletionNotificationItem: Bool]
    @State private var notificationAuthorizationStatus: CompletionNotificationAuthorizationStatus = .unknown
    @State private var isNotificationPermissionGuidePresented = false
    @State private var isEditingWindowBackgroundMaterialAmount = false
    @State private var isEditingWindowBackgroundBlurLevel = false

    init(
        windowBackgroundMaterialAmount: Binding<Double>,
        isWindowBackgroundBlurEnabled: Binding<Bool>,
        windowBackgroundBlurLevel: Binding<WindowBackgroundBlurLevel>,
        isWindowFullScreen: Bool,
        openKeyboardShortcutManager: @escaping @MainActor () -> Void,
        preferences: CompletionNotificationPreferenceProviding = UserDefaultsCompletionNotificationPreferences.shared,
        notificationReporter: CompletionNotificationReporting = NotificationService.shared
    ) {
        _windowBackgroundMaterialAmount = windowBackgroundMaterialAmount
        _isWindowBackgroundBlurEnabled = isWindowBackgroundBlurEnabled
        _windowBackgroundBlurLevel = windowBackgroundBlurLevel
        self.isWindowFullScreen = isWindowFullScreen
        self.openKeyboardShortcutManager = openKeyboardShortcutManager
        self.preferences = preferences
        self.notificationReporter = notificationReporter
        _completionNotificationsEnabled = State(initialValue: preferences.completionNotificationsEnabled)
        _completionNotificationItemStates = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: CompletionNotificationItem.allCases.map { item in
                    (item, preferences.isEnabled(for: item))
                }
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("アプリ")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 6) {
                LabeledContent {
                    Text("\(AppAppearanceSettings.windowBackgroundMaterialPercent(windowBackgroundMaterialAmount))%")
                        .font(.title3)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } label: {
                    Text("アプリ背景の透明感")
                        .font(.title3)
                }

                Slider(
                    value: windowBackgroundMaterialAmountBinding,
                    in: AppAppearanceSettings.windowBackgroundMaterialRange,
                    step: 0.01,
                    onEditingChanged: handleWindowBackgroundMaterialEditingChanged
                )
                .tint(LiquidGlassSegmentedPickerStyle.sliderTint)
                .disabled(isWindowFullScreen)
                .accessibilityLabel("アプリ背景の透明感")
                .accessibilityValue(backgroundMaterialAccessibilityValue)
                .accessibilityHint(backgroundMaterialAccessibilityHint)
                .onChange(of: windowBackgroundMaterialAmount) { _, newValue in
                    guard !isEditingWindowBackgroundMaterialAmount else { return }
                    AppAppearanceSettings.saveWindowBackgroundMaterialAmount(newValue)
                }
                .onDisappear {
                    AppAppearanceSettings.saveWindowBackgroundMaterialAmount(windowBackgroundMaterialAmount)
                }

                Text("0%で現在と同じ完全透明です。数値を上げると、アプリ全体の背景だけが濃くなります。")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Toggle("ぼかし具合を調整", isOn: $isWindowBackgroundBlurEnabled)
                    .font(.title3)
                    .toggleStyle(.switch)
                    .tint(LiquidGlassSegmentedPickerStyle.switchTint)
                    .disabled(isWindowFullScreen)
                    .accessibilityHint(backgroundBlurToggleAccessibilityHint)
                    .onChange(of: isWindowBackgroundBlurEnabled) { _, isEnabled in
                        AppAppearanceSettings.saveWindowBackgroundBlurEnabled(isEnabled)
                    }

                if isWindowBackgroundBlurEnabled {
                    LabeledContent {
                        Text(windowBackgroundBlurLevel.title)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text("ぼかし具合")
                            .font(.title3)
                    }

                    Slider(
                        value: windowBackgroundBlurLevelBinding,
                        in: WindowBackgroundBlurLevel.sliderRange,
                        step: 1
                    ) {
                        EmptyView()
                    } tick: { position in
                        SliderTick(position) {
                            Text(WindowBackgroundBlurLevel.level(for: position).title)
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    } onEditingChanged: { isEditing in
                        handleWindowBackgroundBlurLevelEditingChanged(isEditing)
                    }
                    .tint(LiquidGlassSegmentedPickerStyle.sliderTint)
                    .disabled(isWindowFullScreen)
                    .accessibilityLabel("背景のぼかし具合")
                    .accessibilityValue(windowBackgroundBlurLevel.title)
                    .accessibilityHint(backgroundBlurLevelAccessibilityHint)
                    .onChange(of: windowBackgroundBlurLevel) { _, newValue in
                        guard !isEditingWindowBackgroundBlurLevel else { return }
                        AppAppearanceSettings.saveWindowBackgroundBlurLevel(newValue)
                    }
                    .onDisappear {
                        AppAppearanceSettings.saveWindowBackgroundBlurLevel(windowBackgroundBlurLevel)
                    }
                }

                Text(isWindowBackgroundBlurEnabled
                     ? "ぼかし具合を5段階で調整します。"
                     : "従来の透明感設定を使用しています。")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Divider()

            notificationSettings

            Divider()

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("キーボード操作")
                        .font(.title3)
                    Text("変更できるショートカットと固定操作を確認します")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                LiquidGlassActionButton(
                    title: "ショートカットを管理…",
                    systemImage: "keyboard",
                    action: openKeyboardShortcutManager
                )
                .accessibilityLabel("ショートカットを管理")
            }
        }
        .task {
            await refreshNotificationAuthorizationStatus()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            Task { @MainActor in
                await refreshNotificationAuthorizationStatus()
            }
        }
        .alert(
            "macOSの通知が許可されていません",
            isPresented: $isNotificationPermissionGuidePresented
        ) {
            Button("キャンセル", role: .cancel) {}
            Button("システム設定を開く") {
                openSystemNotificationSettings()
            }
        } message: {
            Text("通知を受け取るには、システム設定の「通知」でVeloura Lucentを許可してください。")
        }
    }

    private var backgroundMaterialAccessibilityValue: String {
        let percent = AppAppearanceSettings.windowBackgroundMaterialPercent(windowBackgroundMaterialAmount)
        if percent == 0 {
            return "0パーセント、現在と同じ完全透明"
        }
        return "\(percent)パーセント、アプリ全体の背景だけを濃くします"
    }

    private var backgroundMaterialAccessibilityHint: String {
        if isWindowFullScreen {
            return "フルスクリーン中は変更できません。通常表示に戻すと変更できます。"
        }
        return "アプリ全体の背景の濃さを変更します。"
    }

    private var backgroundBlurToggleAccessibilityHint: String {
        if isWindowFullScreen {
            return "フルスクリーン中は変更できません。通常表示に戻すと変更できます。"
        }
        return "5段階のぼかし調整を切り替えます。オフでは従来の透明感設定を使用します。"
    }

    private var backgroundBlurLevelAccessibilityHint: String {
        if isWindowFullScreen {
            return "フルスクリーン中は変更できません。通常表示に戻すと変更できます。"
        }
        return "アプリ全体の背景のぼかし具合を5段階で変更します。"
    }

    private var windowBackgroundMaterialAmountBinding: Binding<Double> {
        Binding(
            get: { windowBackgroundMaterialAmount },
            set: { newValue in
                windowBackgroundMaterialAmount = AppAppearanceSettings
                    .clampedWindowBackgroundMaterialAmount(newValue)
            }
        )
    }

    private var windowBackgroundBlurLevelBinding: Binding<Double> {
        Binding(
            get: { windowBackgroundBlurLevel.sliderPosition },
            set: { newValue in
                windowBackgroundBlurLevel = WindowBackgroundBlurLevel.level(for: newValue)
            }
        )
    }

    private func handleWindowBackgroundMaterialEditingChanged(_ isEditing: Bool) {
        isEditingWindowBackgroundMaterialAmount = isEditing
        if !isEditing {
            AppAppearanceSettings.saveWindowBackgroundMaterialAmount(windowBackgroundMaterialAmount)
        }
    }

    private func handleWindowBackgroundBlurLevelEditingChanged(_ isEditing: Bool) {
        isEditingWindowBackgroundBlurLevel = isEditing
        if !isEditing {
            AppAppearanceSettings.saveWindowBackgroundBlurLevel(windowBackgroundBlurLevel)
        }
    }

    private var completionNotificationsBinding: Binding<Bool> {
        Binding(
            get: { completionNotificationsEnabled },
            set: { newValue in
                completionNotificationsEnabled = newValue
                preferences.completionNotificationsEnabled = newValue
                if newValue {
                    Task { @MainActor in
                        await prepareNotificationsIfNeeded()
                    }
                }
            }
        )
    }

    private var notificationSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("通知")
                .font(.title3.bold())

            LabeledContent {
                Text(notificationAuthorizationStatus.title)
                    .font(.title3)
                    .foregroundStyle(
                        notificationAuthorizationStatus == .authorized
                            ? Color.green
                            : Color.red
                    )
            } label: {
                Text("macOSの通知許可")
                    .font(.title3)
            }

            Text("通知項目")
                .font(.title3.weight(.semibold))

            VStack(spacing: 0) {
                notificationToggleRow(
                    title: "アプリ通知",
                    isOn: completionNotificationsBinding
                )

                Divider()

                ForEach(CompletionNotificationItem.allCases) { item in
                    notificationToggleRow(
                        title: item.title,
                        isOn: completionNotificationItemBinding(for: item),
                        isEnabled: completionNotificationsEnabled
                    )

                    if item.id != CompletionNotificationItem.allCases.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private func notificationToggleRow(
        title: String,
        isOn: Binding<Bool>,
        isEnabled: Bool = true
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.title3)

            Spacer(minLength: 12)

            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(LiquidGlassSegmentedPickerStyle.switchTint)
                .accessibilityLabel(title)
        }
        .padding(.vertical, 10)
        .disabled(!isEnabled)
    }

    private func completionNotificationItemBinding(
        for item: CompletionNotificationItem
    ) -> Binding<Bool> {
        Binding(
            get: { completionNotificationItemStates[item] ?? true },
            set: { isEnabled in
                completionNotificationItemStates[item] = isEnabled
                preferences.setEnabled(isEnabled, for: item)
            }
        )
    }

    @MainActor
    private func prepareNotificationsIfNeeded() async {
        let status = await notificationReporter.authorizationStatus()
        notificationAuthorizationStatus = status

        switch status {
        case .authorized:
            return
        case .notDetermined:
            let isAuthorized = await notificationReporter.requestAuthorization()
            await refreshNotificationAuthorizationStatus()
            if !isAuthorized {
                isNotificationPermissionGuidePresented = true
            }
        case .denied, .unknown:
            isNotificationPermissionGuidePresented = true
        }
    }

    @MainActor
    private func refreshNotificationAuthorizationStatus() async {
        notificationAuthorizationStatus = await notificationReporter.authorizationStatus()
    }

    private func openSystemNotificationSettings() {
        let rootURLString = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"

        guard let rootURL = URL(string: rootURLString) else { return }

        guard
            let bundleIdentifier = Bundle.main.bundleIdentifier,
            var components = URLComponents(string: rootURLString)
        else {
            NSWorkspace.shared.open(rootURL)
            return
        }

        components.queryItems = [
            URLQueryItem(name: "id", value: bundleIdentifier)
        ]

        guard
            let appSettingsURL = components.url,
            NSWorkspace.shared.open(appSettingsURL)
        else {
            NSWorkspace.shared.open(rootURL)
            return
        }
    }
}
