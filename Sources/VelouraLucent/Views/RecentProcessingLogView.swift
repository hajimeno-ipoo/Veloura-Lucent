import SwiftUI

struct RecentProcessingLogView: View {
    let events: [RecentActivityEvent]
    @Binding var isFullLogPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("直近ログ")
                    .font(.headline)
                Spacer()
                Button("詳細ログ", systemImage: "list.bullet.rectangle") {
                    isFullLogPresented = true
                }
                .buttonStyle(.borderless)
                .help("補正とマスタリングの完全なログを開きます")
            }

            if events.isEmpty {
                Text("音声を選ぶと、直近の処理内容を最大3件表示します")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(events.suffix(3)) { event in
                        HStack(alignment: .center, spacing: 8) {
                            Text(event.timestamp, style: .time)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 58, alignment: .leading)

                            Image(systemName: event.hasFailed ? "xmark.circle.fill" : event.domain.systemImage)
                                .foregroundStyle(event.hasFailed ? Color.red : event.domain.tint)
                                .frame(width: 14)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                if let summary = summary(for: event) {
                                    Text(summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .help(summary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if let progress = event.progress, event.isRunning || event.hasFailed {
                                HStack(spacing: 5) {
                                    ProgressView(value: progress)
                                        .frame(width: 54)
                                    Text("\(Int((progress * 100).rounded()))%")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(event.hasFailed ? Color.red : event.domain.tint)
                                        .frame(width: 34, alignment: .trailing)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("進捗")
                                .accessibilityValue("\(Int((progress * 100).rounded()))パーセント")
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
            }
        }
    }

    private func summary(for event: RecentActivityEvent) -> String? {
        var values: [String] = []
        if let fileName = event.fileName {
            values.append(fileName)
        }
        if let audioSummary = event.audioSummary {
            values.append(audioSummary)
        }
        if let detail = event.detail, detail != event.fileName {
            values.append(detail)
        }
        return values.isEmpty ? nil : values.joined(separator: " / ")
    }
}

private extension RecentActivityDomain {
    var systemImage: String {
        switch self {
        case .input: "waveform"
        case .correction: "wand.and.sparkles"
        case .mastering: "slider.horizontal.3"
        case .export: "square.and.arrow.up"
        }
    }

    var tint: Color {
        switch self {
        case .input: .blue
        case .correction: .green
        case .mastering: .orange
        case .export: .purple
        }
    }
}
