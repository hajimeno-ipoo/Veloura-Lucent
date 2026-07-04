import SwiftUI

struct AppSettingsPanel: View {
    private let preferences: CompletionNotificationPreferenceProviding
    private let notificationReporter: CompletionNotificationReporting
    @Binding private var windowBackgroundMaterialAmount: Double
    @State private var completionNotificationsEnabled: Bool
    @State private var isEditingWindowBackgroundMaterialAmount = false

    init(
        windowBackgroundMaterialAmount: Binding<Double>,
        preferences: CompletionNotificationPreferenceProviding = UserDefaultsCompletionNotificationPreferences.shared,
        notificationReporter: CompletionNotificationReporting = NotificationService.shared
    ) {
        _windowBackgroundMaterialAmount = windowBackgroundMaterialAmount
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
                .accessibilityLabel("アプリ背景の透明感")
                .accessibilityValue(backgroundMaterialAccessibilityValue)
                .onChange(of: windowBackgroundMaterialAmount) { _, newValue in
                    guard !isEditingWindowBackgroundMaterialAmount else { return }
                    AppAppearanceSettings.saveWindowBackgroundMaterialAmount(newValue)
                }
                .onDisappear {
                    AppAppearanceSettings.saveWindowBackgroundMaterialAmount(windowBackgroundMaterialAmount)
                }

                Text("0%で現在と同じ完全透明です。数値を上げると、アプリ全体の背景だけが曇ります。")
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
        return "\(percent)パーセント、アプリ全体の背景だけを曇らせます"
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

    private func handleWindowBackgroundMaterialEditingChanged(_ isEditing: Bool) {
        isEditingWindowBackgroundMaterialAmount = isEditing
        if !isEditing {
            AppAppearanceSettings.saveWindowBackgroundMaterialAmount(windowBackgroundMaterialAmount)
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
