import SwiftUI

struct ProcessingLogView: View {
    let correctionLines: [String]
    let masteringLines: [String]

    var body: some View {
        logSection
    }
    private var logSection: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 360), spacing: 14)],
            alignment: .leading,
            spacing: 14
        ) {
            logCard(title: "補正ログ", lines: correctionLines, placeholder: "ここに補正ログが表示されます。")
            logCard(title: "マスタリングログ", lines: masteringLines, placeholder: "ここにマスタリングログが表示されます。")
        }
    }

    private func logCard(title: String, lines: [String], placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ScrollView {
                if lines.isEmpty {
                    Text(placeholder)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                } else {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(12)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

}
