import SwiftUI

struct FullProcessingLogView: View {
    let correctionLines: [String]
    let masteringLines: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("処理ログ")
                    .font(.title2.bold())
                Spacer()
                Button("閉じる", action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Divider()

            ScrollView {
                ProcessingLogView(
                    correctionLines: correctionLines,
                    masteringLines: masteringLines
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 640, idealWidth: 840, minHeight: 520, idealHeight: 680)
    }
}
