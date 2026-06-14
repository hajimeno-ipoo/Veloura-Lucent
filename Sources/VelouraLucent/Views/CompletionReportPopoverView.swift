import SwiftUI

struct CompletionReportPopoverView: View {
    let report: CompletionReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("完了後レポート")
                        .font(.title3.bold())
                    Spacer()
                    Text(severityText(report.severity))
                        .font(.callout.bold())
                        .foregroundStyle(severityColor(report.severity))
                }

                reportSection(title: "音量とピーク", rows: report.loudnessRows)
                reportSection(title: "ノイズ", rows: report.noiseRows)
                reportSection(title: "高域保持", rows: report.highFrequencyRows)

                Text(report.reminder)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(18)
        }
        .frame(width: 540, height: 620)
    }

    private func reportSection(title: String, rows: [CompletionReportRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(severityColor(row.severity))
                        .frame(width: 8, height: 8)
                        .padding(.top, 7)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.title)
                                .font(.body.bold())
                            Spacer()
                            Text(row.value)
                                .font(.body.monospacedDigit().bold())
                                .foregroundStyle(severityColor(row.severity))
                        }
                        Text(row.detail)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func severityText(_ severity: CompletionReportSeverity) -> String {
        switch severity {
        case .normal:
            return "確認"
        case .caution:
            return "注意"
        case .warning:
            return "警告"
        }
    }

    private func severityColor(_ severity: CompletionReportSeverity) -> Color {
        switch severity {
        case .normal:
            return .green
        case .caution:
            return .orange
        case .warning:
            return .red
        }
    }
}
