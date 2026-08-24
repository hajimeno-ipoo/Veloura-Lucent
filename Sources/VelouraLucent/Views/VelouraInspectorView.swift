import SwiftUI

struct VelouraInspectorView: View {
    @Bindable var job: ProcessingJob
    @Binding var windowBackgroundMaterialAmount: Double
    @Binding var isWindowBackgroundBlurEnabled: Bool
    @Binding var windowBackgroundBlurLevel: WindowBackgroundBlurLevel
    @Binding var selectedSettingsSectionRawValue: String
    let isWindowFullScreen: Bool
    let openKeyboardShortcutManager: @MainActor () -> Void

    var body: some View {
        ScrollView {
            InspectorSettingsPanel(
                job: job,
                windowBackgroundMaterialAmount: $windowBackgroundMaterialAmount,
                isWindowBackgroundBlurEnabled: $isWindowBackgroundBlurEnabled,
                windowBackgroundBlurLevel: $windowBackgroundBlurLevel,
                selectedSectionRawValue: $selectedSettingsSectionRawValue,
                isWindowFullScreen: isWindowFullScreen,
                openKeyboardShortcutManager: openKeyboardShortcutManager
            )
            .padding(14)
            .velouraTransientOverlayScrollIndicators()
        }
        .scrollContentBackground(.hidden)
    }
}
