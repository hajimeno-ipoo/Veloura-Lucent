import SwiftUI

struct SidebarProcessingStatusView: View {
    @Bindable var job: ProcessingJob

    var body: some View {
        Group {
            if job.isProcessing || job.isMastering {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    statusRows(now: timeline.date)
                }
            } else {
                statusRows(now: .now)
            }
        }
    }

    private func statusRows(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SidebarProcessStatusRow(
                title: "補正",
                status: job.statusMessage,
                activeStepTitle: job.activeStep?.title,
                activeStepDetail: job.activeStepDetail,
                startedAt: job.processingStartedAt,
                finishedAt: job.processingFinishedAt,
                isRunning: job.isProcessing,
                isComplete: job.statusMessage == "完了",
                hasFailed: !job.failedSteps.isEmpty || job.lastError != nil,
                progress: job.progressValue,
                steps: correctionSteps,
                tint: correctionTint,
                now: now
            )

            Divider()

            SidebarProcessStatusRow(
                title: "マスタリング",
                status: job.masteringStatusMessage,
                activeStepTitle: job.masteringActiveStep?.title,
                activeStepDetail: job.masteringActiveStepDetail,
                startedAt: job.masteringStartedAt,
                finishedAt: job.masteringFinishedAt,
                isRunning: job.isMastering,
                isComplete: job.masteringStatusMessage == "完了",
                hasFailed: !job.failedMasteringSteps.isEmpty || job.masteringLastError != nil,
                progress: job.masteringProgressValue,
                steps: masteringSteps,
                tint: masteringTint,
                now: now
            )
        }
    }

    private var correctionSteps: [SidebarProcessStepDisplay] {
        ProcessingStep.allCases.map { step in
            SidebarProcessStepDisplay(
                id: step.eventID,
                title: step.title,
                detail: job.activeStep == step ? job.activeStepDetail : nil,
                state: stepState(
                    step: step,
                    activeStep: job.activeStep,
                    completedSteps: job.completedSteps,
                    skippedSteps: job.skippedSteps,
                    failedSteps: job.failedSteps
                )
            )
        }
    }

    private var masteringSteps: [SidebarProcessStepDisplay] {
        MasteringStep.allCases.map { step in
            SidebarProcessStepDisplay(
                id: step.eventID,
                title: step.title,
                detail: job.masteringActiveStep == step ? job.masteringActiveStepDetail : nil,
                state: stepState(
                    step: step,
                    activeStep: job.masteringActiveStep,
                    completedSteps: job.completedMasteringSteps,
                    skippedSteps: job.skippedMasteringSteps,
                    failedSteps: job.failedMasteringSteps
                )
            )
        }
    }

    private func stepState<Step: Hashable>(
        step: Step,
        activeStep: Step?,
        completedSteps: Set<Step>,
        skippedSteps: Set<Step>,
        failedSteps: Set<Step>
    ) -> SidebarProcessStepState {
        if failedSteps.contains(step) {
            return .failed
        }
        if activeStep == step {
            return .active
        }
        if completedSteps.contains(step) {
            return .completed
        }
        if skippedSteps.contains(step) {
            return .skipped
        }
        return .pending
    }

    private var correctionTint: Color {
        if job.isProcessing {
            return ProcessingStatusColors.active
        }
        if job.lastError != nil {
            return .red
        }
        if job.hasExistingOutput {
            return ProcessingStatusColors.complete
        }
        return .secondary
    }

    private var masteringTint: Color {
        if job.isMastering {
            return ProcessingStatusColors.active
        }
        if job.masteringLastError != nil {
            return .red
        }
        if job.hasExistingMasteredOutput {
            return ProcessingStatusColors.complete
        }
        return .secondary
    }

}
