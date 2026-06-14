import SwiftUI

struct SidebarProcessStatusRow: View {
    let title: String
    let status: String
    let activeStepTitle: String?
    let activeStepDetail: String?
    let startedAt: Date?
    let finishedAt: Date?
    let isRunning: Bool
    let isComplete: Bool
    let hasFailed: Bool
    let progress: Double
    let steps: [SidebarProcessStepDisplay]
    let tint: Color
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 7) {
                    Image(systemName: statusIcon)
                        .accessibilityHidden(true)
                    Text(title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .layoutPriority(1)
                }
                .font(.callout.bold())
                .foregroundStyle(statusTint)
                Spacer(minLength: 6)
                if let elapsedText {
                    Text(elapsedText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(activeStepTitle.map { "\($0)を実行中" } ?? status)
                .font(.callout)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let activeStepDetail {
                Text(activeStepDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: 8) {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(statusTint)
                Text(progressText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(statusTint)
                    .frame(minWidth: 30, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title)の進捗")
            .accessibilityValue("\(Int((min(max(progress, 0), 1) * 100).rounded()))パーセント")

            VStack(alignment: .leading, spacing: 4) {
                ForEach(steps) { step in
                    SidebarProcessStepRow(step: step, tint: statusTint)
                }
            }
            .padding(.top, 2)

        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var statusIcon: String {
        if hasFailed {
            return "xmark.circle.fill"
        }
        if isRunning {
            return "dot.circle.fill"
        }
        if isComplete {
            return "checkmark.circle.fill"
        }
        return "circle"
    }

    private var statusTint: Color {
        if hasFailed {
            return .red
        }
        return tint
    }

    private var elapsedText: String? {
        guard let startedAt else { return nil }
        let endDate = isRunning ? now : (finishedAt ?? now)
        let elapsedSeconds = max(0, Int(endDate.timeIntervalSince(startedAt)))
        return formattedElapsedTime(elapsedSeconds)
    }

    private var progressText: String {
        "\(Int((min(max(progress, 0), 1) * 100).rounded()))%"
    }

    private func formattedElapsedTime(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

struct SidebarProcessStepDisplay: Identifiable {
    let id: String
    let title: String
    let detail: String?
    let state: SidebarProcessStepState
}

enum SidebarProcessStepState {
    case pending
    case active
    case completed
    case skipped
    case failed

    var iconName: String {
        switch self {
        case .pending:
            "circle"
        case .active:
            "dot.circle.fill"
        case .completed:
            "checkmark.circle.fill"
        case .skipped:
            "minus.circle"
        case .failed:
            "xmark.circle.fill"
        }
    }

    var shortLabel: String? {
        switch self {
        case .pending, .completed:
            nil
        case .active:
            "実行中"
        case .skipped:
            "省略"
        case .failed:
            "失敗"
        }
    }

    func color(tint: Color) -> Color {
        switch self {
        case .pending:
            .secondary.opacity(0.45)
        case .active:
            tint
        case .completed:
            tint
        case .skipped:
            .secondary
        case .failed:
            .red
        }
    }
}

private struct SidebarProcessStepRow: View {
    let step: SidebarProcessStepDisplay
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: step.state.iconName)
                    .font(.caption2)
                    .foregroundStyle(step.state.color(tint: tint))
                    .frame(width: 12)
                    .accessibilityHidden(true)

                Text(step.title)
                    .font(.caption)
                    .foregroundStyle(step.state.color(tint: tint))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                if let shortLabel = step.state.shortLabel {
                    Text(shortLabel)
                        .font(.caption2)
                        .foregroundStyle(step.state.color(tint: tint))
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(step.state.color(tint: tint).opacity(0.12))
                        )
                }
            }

            if step.state == .active, let detail = step.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, 18)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if let shortLabel = step.state.shortLabel {
            return "\(step.title)、\(shortLabel)"
        }
        if step.state == .completed {
            return "\(step.title)、完了"
        }
        return "\(step.title)、待機"
    }
}
