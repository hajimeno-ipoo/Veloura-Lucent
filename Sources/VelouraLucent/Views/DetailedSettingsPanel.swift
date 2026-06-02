import SwiftUI

private enum DetailedSettingsSection: String, CaseIterable, Identifiable {
    case correction
    case mastering
    case app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .correction:
            return "補正"
        case .mastering:
            return "マスタリング"
        case .app:
            return "アプリ"
        }
    }
}

struct DetailedSettingsPanel: View {
    @Bindable var job: ProcessingJob
    @State private var selectedSection: DetailedSettingsSection = .correction

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("詳細設定")
                        .font(.headline)
                    Text("補正、マスタリング、アプリ設定を切り替えて調整します。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("詳細設定", selection: $selectedSection) {
                    ForEach(DetailedSettingsSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            }
            .disabled(job.isProcessing || job.isMastering)

            Group {
                switch selectedSection {
                case .correction:
                    CorrectionSettingsPanel(job: job)
                case .mastering:
                    MasteringSettingsPanel(job: job)
                case .app:
                    AppSettingsPanel()
                }
            }
            .disabled(job.isProcessing || job.isMastering)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }
}
