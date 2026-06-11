import SwiftUI

struct ProcessingProgressView: View {
    @Bindable var job: ProcessingJob

    var body: some View {
        progressSection
    }
    private var progressSection: some View {
        Group {
            if job.isProcessing || job.isMastering {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    progressContent(now: timeline.date)
                }
            } else {
                progressContent(now: .now)
            }
        }
    }

    private func progressContent(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            progressBlock(
                title: "補正の進行状況",
                status: job.progressLabel,
                elapsedText: elapsedProcessingText(
                    startedAt: job.processingStartedAt,
                    finishedAt: job.processingFinishedAt,
                    isRunning: job.isProcessing,
                    didComplete: job.statusMessage == "完了",
                    now: now
                ),
                tint: correctionStatusColor,
                value: job.progressValue,
                steps: ProcessingStep.allCases,
                activeStep: job.activeStep,
                completedSteps: job.completedSteps,
                skippedSteps: job.skippedSteps,
                failedSteps: job.failedSteps
            )

            masteringProgressBlock(now: now)
        }
    }

    private func progressBlock(
        title: String,
        status: String,
        elapsedText: String?,
        tint: Color,
        value: Double,
        steps: [ProcessingStep],
        activeStep: ProcessingStep?,
        completedSteps: Set<ProcessingStep>,
        skippedSteps: Set<ProcessingStep>,
        failedSteps: Set<ProcessingStep>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(status)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    if let elapsedText {
                        Text(elapsedText)
                            .font(.title3.monospacedDigit().weight(.bold))
                            .foregroundStyle(tint)
                    }
                }
            }

            ProgressView(value: value)
                .tint(tint)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(steps, id: \.self) { step in
                        progressBadge(
                            title: step.title,
                            isCompleted: completedSteps.contains(step),
                            isActive: activeStep == step,
                            isSkipped: skippedSteps.contains(step),
                            isFailed: failedSteps.contains(step)
                        )
                    }
                }
            }
        }
    }

    private func masteringProgressBlock(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("マスタリングの進行状況")
                    .font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(masteringProgressLabel)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    if let elapsedText = elapsedProcessingText(
                        startedAt: job.masteringStartedAt,
                        finishedAt: job.masteringFinishedAt,
                        isRunning: job.isMastering,
                        didComplete: job.masteringStatusMessage == "完了",
                        now: now
                    ) {
                        Text(elapsedText)
                            .font(.title3.monospacedDigit().weight(.bold))
                            .foregroundStyle(masteringStatusColor)
                    }
                }
            }

            ProgressView(value: masteringProgressValue)
                .tint(masteringStatusColor)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MasteringStep.allCases, id: \.self) { step in
                        progressBadge(
                            title: step.title,
                            isCompleted: job.completedMasteringSteps.contains(step),
                            isActive: job.masteringActiveStep == step,
                            isSkipped: job.skippedMasteringSteps.contains(step),
                            isFailed: job.failedMasteringSteps.contains(step)
                        )
                    }
                }
            }
        }
    }

    private func progressBadge(title: String, isCompleted: Bool, isActive: Bool, isSkipped: Bool, isFailed: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isFailed ? "xmark.circle.fill" : isSkipped ? "minus.circle.fill" : isCompleted ? "checkmark.circle.fill" : isActive ? "dot.circle.fill" : "circle")
                .foregroundStyle(isFailed ? Color.red : isSkipped ? Color.secondary : isCompleted ? Color.green : isActive ? Color.orange : Color.secondary)
            Text(title)
                .font(.body.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(isFailed ? Color.red.opacity(0.12) : isActive ? Color.orange.opacity(0.14) : isCompleted ? Color.green.opacity(0.14) : Color.secondary.opacity(isSkipped ? 0.14 : 0.08))
        )
    }


    private var correctionStatusColor: Color {
        if job.isProcessing {
            return .orange
        }
        if job.lastError != nil {
            return .red
        }
        if job.hasExistingOutput {
            return .green
        }
        return .secondary
    }

    private var masteringStatusColor: Color {
        if job.isMastering {
            return .orange
        }
        if job.masteringLastError != nil {
            return .red
        }
        if job.hasExistingMasteredOutput {
            return .green
        }
        return .secondary
    }

    private var masteringProgressValue: Double {
        if !job.isMastering && job.masteringStatusMessage == "完了" {
            return 1
        }
        let total = Double(MasteringStep.allCases.count)
        let completed = Double(job.completedMasteringSteps.count)
        let skipped = Double(job.skippedMasteringSteps.count)
        let activeBoost = job.masteringActiveStep == nil ? 0 : 0.5
        return min(0.98, (completed + skipped + activeBoost) / total)
    }

    private var masteringProgressLabel: String {
        if let step = job.masteringActiveStep {
            if let detail = job.masteringActiveStepDetail {
                return "\(step.title): \(detail)"
            }
            return "\(step.title) を実行中"
        }
        return job.masteringStatusMessage
    }

    private func elapsedProcessingText(
        startedAt: Date?,
        finishedAt: Date?,
        isRunning: Bool,
        didComplete: Bool,
        now: Date
    ) -> String? {
        guard let startedAt else { return nil }
        let endDate = isRunning ? now : (finishedAt ?? now)
        let elapsedSeconds = max(0, Int(endDate.timeIntervalSince(startedAt)))
        let prefix: String
        if isRunning {
            prefix = "経過"
        } else {
            prefix = didComplete ? "完了" : "停止"
        }
        return "\(prefix) \(formattedElapsedTime(elapsedSeconds))"
    }

    private func formattedElapsedTime(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return "\(hours)時間\(minutes)分\(remainingSeconds)秒"
        }
        if minutes > 0 {
            return "\(minutes)分\(remainingSeconds)秒"
        }
        return "\(remainingSeconds)秒"
    }

}
