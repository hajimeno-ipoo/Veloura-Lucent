import SwiftUI

struct RecentProcessingLogView: View {
    let events: [RecentActivityEvent]
    let fullLogHelp: String
    @Binding var isFullLogPresented: Bool
    @Environment(\.locale) private var locale

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
                .help(AppLanguageSettings.string(fullLogHelp))
            }

            if events.isEmpty {
                Text("音声を選ぶと、直近の処理内容を最大4件表示します")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(events.suffix(4)) { event in
                        HStack(alignment: .center, spacing: 8) {
                            Text(event.timestamp, style: .time)
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 58, alignment: .leading)

                            Image(systemName: event.hasFailed ? "xmark.circle.fill" : event.domain.systemImage)
                                .foregroundStyle(event.hasFailed ? Color.red : event.domain.tint)
                                .frame(width: 14)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 1) {
                                AppLocalizedText(event.title)
                                    .font(.callout.bold())
                                    .lineLimit(1)
                                if let summary = summary(for: event) {
                                    Text(summary)
                                        .font(.callout)
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
                                        .tint(event.hasFailed ? Color.red : ProcessingStatusColors.active)
                                        .frame(width: 54)
                                    Text("\(Int((progress * 100).rounded()))%")
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(event.hasFailed ? Color.red : ProcessingStatusColors.active)
                                        .frame(width: 34, alignment: .trailing)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("進捗")
                                .accessibilityValue(AppLanguageSettings.format(
                                    "%dパーセント", Int((progress * 100).rounded())
                                ))
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 139, alignment: .topLeading)
            }
        }
        .environment(\.locale, locale)
    }

    private func summary(for event: RecentActivityEvent) -> String? {
        var values: [String] = []
        if let fileName = event.fileName {
            values.append(fileName)
        }
        if let audioSummary = event.audioSummary {
            values.append(AppLanguageSettings.string(audioSummary))
        }
        if let detail = event.detail, detail != event.fileName {
            values.append(ProcessingDetailLocalization.string(detail))
        }
        return values.isEmpty ? nil : values.joined(separator: " / ")
    }
}

enum ProcessingDetailLocalization {
    static func stepTitle(_ title: String) -> String {
        let exactTranslation = AppLanguageSettings.string(title)
        if exactTranslation != title { return exactTranslation }

        if let separator = title.range(of: "：") {
            let role = String(title[..<separator.lowerBound])
            let stage = String(title[separator.upperBound...])
            return AppLanguageSettings.format(
                "%@：%@",
                AppLanguageSettings.string(role),
                AppLanguageSettings.string(stage)
            )
        }

        if title.hasSuffix("Stem分離"),
           let count = Int(title.dropLast("Stem分離".count)) {
            return AppLanguageSettings.format("%dStem分離", count)
        }

        return title
    }

    static func string(_ detail: String) -> String {
        let exactTranslation = AppLanguageSettings.string(detail)
        if exactTranslation != detail { return exactTranslation }

        if detail.hasPrefix("補正済み"),
           detail.hasSuffix("Stemと補正後を保存しました"),
           let count = Int(detail.dropFirst("補正済み".count).dropLast("Stemと補正後を保存しました".count)) {
            return AppLanguageSettings.format("補正済み%dStemと補正後を保存しました", count)
        }

        if detail.hasPrefix("ラウドネス: "),
           let peakRange = detail.range(of: " LUFS / ピーク: "),
           detail.hasSuffix(" dBTP") {
            let loudnessStart = detail.index(detail.startIndex, offsetBy: "ラウドネス: ".count)
            let loudness = String(detail[loudnessStart..<peakRange.lowerBound])
            let peak = String(detail[peakRange.upperBound..<detail.index(detail.endIndex, offsetBy: -" dBTP".count)])
            return AppLanguageSettings.format(
                "ラウドネス: %@ LUFS / ピーク: %@ dBTP",
                loudness,
                peak
            )
        }

        if let separator = detail.range(of: ": ") {
            let title = String(detail[..<separator.lowerBound])
            let remaining = String(detail[separator.upperBound...])
            let translatedTitle = stepTitle(title)
            if translatedTitle != title {
                return "\(translatedTitle): \(AppLanguageSettings.string(remaining))"
            }
        }

        for (suffix, format) in [
            ("を実行中", "%@を実行中"),
            ("が完了", "%@が完了"),
            ("を省略", "%@を省略"),
            ("に失敗", "%@に失敗")
        ] where detail.hasSuffix(suffix) {
            let title = String(detail.dropLast(suffix.count))
            let translatedTitle = stepTitle(title)
            if translatedTitle != title {
                return AppLanguageSettings.format(format, translatedTitle)
            }
        }

        return detail
    }
}

private extension RecentActivityDomain {
    var systemImage: String {
        switch self {
        case .input: "waveform"
        case .correction: "wand.and.sparkles"
        case .remix: "slider.horizontal.3"
        case .mastering: "waveform.badge.checkmark"
        case .export: "square.and.arrow.up"
        }
    }

    var tint: Color {
        switch self {
        case .input: .blue
        case .correction: .green
        case .remix: .cyan
        case .mastering: .orange
        case .export: .purple
        }
    }
}
