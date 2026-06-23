import SwiftUI

struct VelouraInspectorView: View {
    @Bindable var job: ProcessingJob
    let completionReport: CompletionReport?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InspectorSettingsPanel(job: job)
                Divider()
                InspectorAnalysisPanel(job: job, completionReport: completionReport)
            }
            .padding(14)
        }
        .scrollContentBackground(.hidden)
    }
}
