import SwiftUI

struct VelouraInspectorView: View {
    @Bindable var job: ProcessingJob

    var body: some View {
        ScrollView {
            InspectorSettingsPanel(job: job)
                .padding(18)
        }
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 440)
        .inspectorColumnWidth(min: 320, ideal: 360, max: 440)
    }
}
