import SwiftUI

struct FullProcessingLogView: View {
    @Bindable var job: ProcessingJob
    let onDismiss: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("処理ログ")
                        .font(.title2.bold())
                    Spacer()
                    Button("閉じる", action: onDismiss)
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.glass)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                ScrollView {
                    ProcessingLogView(
                        correctionLines: job.logLines,
                        masteringLines: job.masteringLogLines
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .scrollContentBackground(.hidden)
            }
            .glassEffect(.clear, in: .rect(cornerRadius: 18))
        }
        .frame(minWidth: 640, idealWidth: 840, minHeight: 520, idealHeight: 680)
        .padding(18)
    }
}
