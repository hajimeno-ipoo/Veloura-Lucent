import SwiftUI

struct VelouraInspectorView: View {
    @Bindable var job: ProcessingJob
    let completionReport: CompletionReport?
    @Binding var windowBackgroundMaterialAmount: Double
    @Binding var isWindowBackgroundBlurEnabled: Bool
    @Binding var windowBackgroundBlurLevel: WindowBackgroundBlurLevel
    @Binding var selectedSettingsSectionRawValue: String
    @Binding var selectedAnalysisAudio: InspectorAudioSelection
    @Binding var isCompletionReportPresented: Bool
    let isWindowFullScreen: Bool
    let openKeyboardShortcutManager: @MainActor () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InspectorSettingsPanel(
                    job: job,
                    windowBackgroundMaterialAmount: $windowBackgroundMaterialAmount,
                    isWindowBackgroundBlurEnabled: $isWindowBackgroundBlurEnabled,
                    windowBackgroundBlurLevel: $windowBackgroundBlurLevel,
                    selectedSectionRawValue: $selectedSettingsSectionRawValue,
                    isWindowFullScreen: isWindowFullScreen,
                    openKeyboardShortcutManager: openKeyboardShortcutManager
                )
                Divider()
                InspectorAnalysisPanel(
                    job: job,
                    completionReport: completionReport,
                    selectedAudio: $selectedAnalysisAudio,
                    isCompletionReportPresented: $isCompletionReportPresented
                )
            }
            .padding(14)
            .velouraTransientOverlayScrollIndicators()
        }
        .scrollContentBackground(.hidden)
    }
}
