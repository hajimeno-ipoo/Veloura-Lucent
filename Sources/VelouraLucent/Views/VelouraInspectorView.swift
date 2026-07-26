import SwiftUI

struct VelouraInspectorView: View {
    @Bindable var job: ProcessingJob
    let completionReport: CompletionReport?
    @Binding var windowBackgroundMaterialAmount: Double
    @Binding var isWindowBackgroundBlurEnabled: Bool
    @Binding var windowBackgroundBlurLevel: WindowBackgroundBlurLevel
    let isWindowFullScreen: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InspectorSettingsPanel(
                    job: job,
                    windowBackgroundMaterialAmount: $windowBackgroundMaterialAmount,
                    isWindowBackgroundBlurEnabled: $isWindowBackgroundBlurEnabled,
                    windowBackgroundBlurLevel: $windowBackgroundBlurLevel,
                    isWindowFullScreen: isWindowFullScreen
                )
                Divider()
                InspectorAnalysisPanel(job: job, completionReport: completionReport)
            }
            .padding(14)
            .velouraTransientOverlayScrollIndicators()
        }
        .scrollContentBackground(.hidden)
    }
}
