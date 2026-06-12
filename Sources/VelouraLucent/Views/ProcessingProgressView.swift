import SwiftUI

struct ProcessingProgressView: View {
    @Bindable var job: ProcessingJob
    @State private var showsCorrectionSteps = false
    @State private var showsMasteringSteps = false

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
        VStack(alignment: .leading, spacing: 16) {
            progressBlock(
                title: "補正",
                status: job.statusMessage,
                activeStepTitle: job.activeStep?.title,
                activeStepDetail: job.activeStepDetail,
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
                failedSteps: job.failedSteps,
                showsSteps: $showsCorrectionSteps
            )

            masteringProgressBlock(now: now)
        }
    }

    private func progressBlock(
        title: String,
        status: String,
        activeStepTitle: String?,
        activeStepDetail: String?,
        elapsedText: String?,
        tint: Color,
        value: Double,
        steps: [ProcessingStep],
        activeStep: ProcessingStep?,
        completedSteps: Set<ProcessingStep>,
        skippedSteps: Set<ProcessingStep>,
        failedSteps: Set<ProcessingStep>,
        showsSteps: Binding<Bool>
    ) -> some View {
        let hasStepHistory = activeStep != nil || !completedSteps.isEmpty || !skippedSteps.isEmpty || !failedSteps.isEmpty

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                progressStatusHeader(
                    title: title,
                    status: status,
                    activeStepTitle: activeStepTitle,
                    activeStepDetail: activeStepDetail,
                    elapsedText: elapsedText,
                    tint: tint,
                    failedCount: failedSteps.count
                )
            }

            progressCountsRow(
                completed: completedSteps.count,
                skipped: skippedSteps.count,
                failed: failedSteps.count
            )

            HStack(spacing: 8) {
                ProgressView(value: value)
                    .tint(tint)
                Text(progressPercentText(value))
                    .font(.callout.monospacedDigit().bold())
                    .foregroundStyle(tint)
                    .frame(width: 44, alignment: .trailing)
            }

            if activeStep == nil && hasStepHistory {
                Label(
                    compactProgressSummary(completed: completedSteps.count, skipped: skippedSteps.count, failed: failedSteps.count),
                    systemImage: failedSteps.isEmpty ? "checkmark.circle" : "exclamationmark.circle"
                )
                .font(.callout)
                .foregroundStyle(failedSteps.isEmpty ? Color.secondary : Color.red)
            }

            if hasStepHistory {
                DisclosureGroup(isExpanded: showsSteps) {
                    VStack(alignment: .leading, spacing: 7) {
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
                    .padding(.top, 6)
                } label: {
                    Text("工程詳細")
                        .font(.callout.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func masteringProgressBlock(now: Date) -> some View {
        let hasStepHistory = job.masteringActiveStep != nil
            || !job.completedMasteringSteps.isEmpty
            || !job.skippedMasteringSteps.isEmpty
            || !job.failedMasteringSteps.isEmpty

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                progressStatusHeader(
                    title: "マスタリング",
                    status: job.masteringStatusMessage,
                    activeStepTitle: job.masteringActiveStep?.title,
                    activeStepDetail: job.masteringActiveStepDetail,
                    elapsedText: elapsedProcessingText(
                        startedAt: job.masteringStartedAt,
                        finishedAt: job.masteringFinishedAt,
                        isRunning: job.isMastering,
                        didComplete: job.masteringStatusMessage == "完了",
                        now: now
                    ),
                    tint: masteringStatusColor,
                    failedCount: job.failedMasteringSteps.count
                )
            }

            progressCountsRow(
                completed: job.completedMasteringSteps.count,
                skipped: job.skippedMasteringSteps.count,
                failed: job.failedMasteringSteps.count
            )

            HStack(spacing: 8) {
                ProgressView(value: masteringProgressValue)
                    .tint(masteringStatusColor)
                Text(progressPercentText(masteringProgressValue))
                    .font(.callout.monospacedDigit().bold())
                    .foregroundStyle(masteringStatusColor)
                    .frame(width: 44, alignment: .trailing)
            }

            if job.masteringActiveStep == nil && hasStepHistory {
                Label(
                    compactProgressSummary(
                        completed: job.completedMasteringSteps.count,
                        skipped: job.skippedMasteringSteps.count,
                        failed: job.failedMasteringSteps.count
                    ),
                    systemImage: job.failedMasteringSteps.isEmpty ? "checkmark.circle" : "exclamationmark.circle"
                )
                .font(.callout)
                .foregroundStyle(job.failedMasteringSteps.isEmpty ? Color.secondary : Color.red)
            }

            if hasStepHistory {
                DisclosureGroup(isExpanded: $showsMasteringSteps) {
                    VStack(alignment: .leading, spacing: 7) {
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
                    .padding(.top, 6)
                } label: {
                    Text("工程詳細")
                        .font(.callout.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressBadge(title: String, isCompleted: Bool, isActive: Bool, isSkipped: Bool, isFailed: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isFailed ? "xmark.circle.fill" : isSkipped ? "minus.circle.fill" : isCompleted ? "checkmark.circle.fill" : isActive ? "dot.circle.fill" : "circle")
                .foregroundStyle(isFailed ? Color.red : isSkipped ? Color.secondary : isCompleted ? Color.green : isActive ? Color.orange : Color.secondary)
            Text(title)
                .font(.callout)
        }
    }

    private func progressStatusHeader(
        title: String,
        status: String,
        activeStepTitle: String?,
        activeStepDetail: String?,
        elapsedText: String?,
        tint: Color,
        failedCount: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                if let elapsedText {
                    Text(elapsedText)
                        .font(.callout.monospacedDigit().bold())
                        .foregroundStyle(tint)
                }
            }

            Label {
                Text(primaryProgressText(status: status, activeStepTitle: activeStepTitle))
                    .font(.callout.bold())
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                Image(systemName: progressStatusIcon(status: status, activeStepTitle: activeStepTitle, failedCount: failedCount))
                    .foregroundStyle(progressStatusTint(status: status, failedCount: failedCount, defaultTint: tint))
            }

            if let activeStepDetail {
                Text(activeStepDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func primaryProgressText(status: String, activeStepTitle: String?) -> String {
        if let activeStepTitle {
            return "\(activeStepTitle)を実行中"
        }
        return status
    }

    private func progressStatusIcon(status: String, activeStepTitle: String?, failedCount: Int) -> String {
        if failedCount > 0 || status == "失敗" {
            return "xmark.circle.fill"
        }
        if activeStepTitle != nil {
            return "dot.circle.fill"
        }
        if status == "完了" {
            return "checkmark.circle.fill"
        }
        return "circle"
    }

    private func progressStatusTint(status: String, failedCount: Int, defaultTint: Color) -> Color {
        if failedCount > 0 || status == "失敗" {
            return .red
        }
        return defaultTint
    }

    private func progressCountsRow(completed: Int, skipped: Int, failed: Int) -> some View {
        let completedTint = completed > 0 ? Color.green : Color.secondary
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                progressCount("完了", completed, tint: completedTint)
                progressCount("省略", skipped, tint: .secondary)
                progressCount("失敗", failed, tint: failed > 0 ? .red : .secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                progressCount("完了", completed, tint: completedTint)
                progressCount("省略", skipped, tint: .secondary)
                progressCount("失敗", failed, tint: failed > 0 ? .red : .secondary)
            }
        }
    }

    private func progressCount(_ title: String, _ value: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.callout)
            Text("\(value)")
                .font(.callout.monospacedDigit().bold())
        }
        .foregroundStyle(tint)
        .lineLimit(1)
    }

    private func progressPercentText(_ value: Double) -> String {
        "\(Int((max(0, min(1, value)) * 100).rounded()))%"
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

    private func compactProgressSummary(completed: Int, skipped: Int, failed: Int) -> String {
        if failed > 0 {
            return "失敗した工程があります"
        }
        if completed > 0 || skipped > 0 {
            return "完了 \(completed)件 / 省略 \(skipped)件"
        }
        return "待機中"
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
