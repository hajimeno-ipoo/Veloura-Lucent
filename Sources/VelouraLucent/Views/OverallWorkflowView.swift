import SwiftUI

struct OverallWorkflowView: View {
    let stages: [WorkspaceFooterStage]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("全体進捗")
                .font(.headline)

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                    stageView(stage)
                    if index < stages.count - 1 {
                        Rectangle()
                            .fill(connectorColor(after: stage))
                            .frame(height: 2)
                            .padding(.top, 11)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func stageView(_ stage: WorkspaceFooterStage) -> some View {
        VStack(spacing: 5) {
            Image(systemName: stage.state.systemImage)
                .font(.title3)
                .foregroundStyle(stage.state.color)
                .accessibilityHidden(true)
            Text(stage.title)
                .font(.caption.bold())
                .lineLimit(1)
            Text(stage.state.label)
                .font(.caption)
                .foregroundStyle(stage.state.color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if stage.state.isActive {
                if let progress = stage.progress {
                    ProgressView(value: progress)
                        .tint(stage.state.color)
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(stage.state.color)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(stage.state.color)
                }
            }
        }
        .frame(minWidth: 62, maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: stage))
    }

    private func accessibilityLabel(for stage: WorkspaceFooterStage) -> String {
        guard stage.state.isActive, let progress = stage.progress else {
            return "\(stage.title)、\(stage.state.label)"
        }
        return "\(stage.title)、\(stage.state.label)、\(Int((progress * 100).rounded()))パーセント"
    }

    private func connectorColor(after stage: WorkspaceFooterStage) -> Color {
        switch stage.state {
        case .complete:
            return .green.opacity(0.6)
        case .active:
            return .orange.opacity(0.6)
        case .pending, .failed:
            return .secondary.opacity(0.25)
        }
    }
}
