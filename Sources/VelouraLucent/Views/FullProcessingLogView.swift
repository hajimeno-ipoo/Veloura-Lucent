import SwiftUI

struct FullProcessingLogLayout: View {
    let sections: [ProcessingLogSection]
    let onDismiss: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("処理ログ")
                        .font(.title2.bold())
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                            .velouraAdaptiveGlass(in: Circle(), interactive: true)
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .accessibilityLabel("閉じる")
                    .help("詳細ログを閉じます")
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                ScrollView {
                    ProcessingLogView(sections: sections)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        .velouraTransientOverlayScrollIndicators()
                }
                .scrollContentBackground(.hidden)
            }
            .velouraAdaptiveGlass(in: .rect(cornerRadius: 18))
        }
        .frame(minWidth: 640, idealWidth: 840, minHeight: 520, idealHeight: 680)
        .padding(18)
    }
}

struct FullProcessingLogView: View {
    @Bindable var job: ProcessingJob
    let onDismiss: () -> Void

    var body: some View {
        FullProcessingLogLayout(
            sections: [
                ProcessingLogSection(
                    id: "correction",
                    title: "補正ログ",
                    lines: job.logLines,
                    placeholder: "ここに補正ログが表示されます。"
                ),
                ProcessingLogSection(
                    id: "mastering",
                    title: "マスタリングログ",
                    lines: job.masteringLogLines,
                    placeholder: "ここにマスタリングログが表示されます。"
                ),
            ],
            onDismiss: onDismiss
        )
    }
}
