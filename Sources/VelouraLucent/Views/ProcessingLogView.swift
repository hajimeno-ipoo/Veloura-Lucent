import SwiftUI

struct ProcessingLogView: View {
    let correctionLines: [String]
    let masteringLines: [String]

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 0), spacing: 14, alignment: .top),
                GridItem(.flexible(minimum: 0), spacing: 14, alignment: .top)
            ],
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

            Group {
                if lines.isEmpty {
                    Text(placeholder)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                } else {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(12)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

}
