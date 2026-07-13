import SwiftUI

struct VelouraInspectorView: View {
    @Bindable var job: ProcessingJob
    let completionReport: CompletionReport?
    @Binding var windowBackgroundMaterialAmount: Double
    let isWindowFullScreen: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InspectorSettingsPanel(
                    job: job,
                    windowBackgroundMaterialAmount: $windowBackgroundMaterialAmount,
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
