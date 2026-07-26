import SwiftUI

struct AppSettingsPanel: View {
    private let preferences: CompletionNotificationPreferenceProviding
    private let notificationReporter: CompletionNotificationReporting
    @Binding private var windowBackgroundMaterialAmount: Double
    @Binding private var isWindowBackgroundBlurEnabled: Bool
    @Binding private var windowBackgroundBlurLevel: WindowBackgroundBlurLevel
    private let isWindowFullScreen: Bool
    @State private var completionNotificationsEnabled: Bool
    @State private var isEditingWindowBackgroundMaterialAmount = false
    @State private var isEditingWindowBackgroundBlurLevel = false

    init(
        windowBackgroundMaterialAmount: Binding<Double>,
        isWindowBackgroundBlurEnabled: Binding<Bool>,
        windowBackgroundBlurLevel: Binding<WindowBackgroundBlurLevel>,
        isWindowFullScreen: Bool,
        preferences: CompletionNotificationPreferenceProviding = UserDefaultsCompletionNotificationPreferences.shared,
        notificationReporter: CompletionNotificationReporting = NotificationService.shared
    ) {
        _windowBackgroundMaterialAmount = windowBackgroundMaterialAmount
        _isWindowBackgroundBlurEnabled = isWindowBackgroundBlurEnabled
        _windowBackgroundBlurLevel = windowBackgroundBlurLevel
        self.isWindowFullScreen = isWindowFullScreen
        self.preferences = preferences
        self.notificationReporter = notificationReporter
        _completionNotificationsEnabled = State(initialValue: preferences.completionNotificationsEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("アプリ")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                LabeledContent {
                    Text("\(AppAppearanceSettings.windowBackgroundMaterialPercent(windowBackgroundMaterialAmount))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } label: {
                    Text("アプリ背景の透明感")
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
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle("ぼかし具合を調整", isOn: $isWindowBackgroundBlurEnabled)
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
                            .foregroundStyle(.secondary)
                    } label: {
                        Text("ぼかし具合")
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
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Toggle("完了通知", isOn: completionNotificationsBinding)
                .toggleStyle(.switch)
                .tint(LiquidGlassSegmentedPickerStyle.switchTint)
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
                    notificationReporter.requestAuthorization()
                }
            }
        )
    }
}
