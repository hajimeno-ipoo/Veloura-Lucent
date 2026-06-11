import SwiftUI

struct ProcessingActionsView: View {
    @Bindable var job: ProcessingJob
    let canStartMastering: Bool
    let onStartCorrection: () -> Void
    let onStartMastering: () -> Void
    let onExportCorrected: (AudioExportFormat) -> Void
    let onExportMastered: (AudioExportFormat) -> Void
    let onOpenCorrectedPreview: () -> Void
    let onOpenMasteredPreview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            correctionActionSection
            masteringActionSection
        }
    }

    private var correctionActionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("補正")
                .font(.headline)

            actionButtonRow(
                primaryTitle: job.isProcessing ? "補正中..." : "補正を実行",
                onPrimary: onStartCorrection,
                primaryDisabled: job.inputFile == nil || job.isProcessing || job.isMastering,
                exportTitle: "補正を書き出し",
                onExport: onExportCorrected,
                exportDisabled: !job.hasExistingOutput || job.isProcessing,
                previewTitle: "プレビューを開く",
                onPreview: onOpenCorrectedPreview,
                previewDisabled: !job.hasExistingOutput || job.isProcessing,
                statusText: job.statusMessage,
                statusColor: correctionStatusColor,
                captionText: job.displayAnalysisStatusText ?? "ノイズ除去は「\(job.selectedDenoiseStrength.title)」です"
            )
        }
    }

    private var masteringActionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("マスタリング")
                .font(.headline)

            actionButtonRow(
                primaryTitle: job.isMastering ? "マスタリング中..." : "マスタリングを実行",
                onPrimary: onStartMastering,
                primaryDisabled: !canStartMastering,
                exportTitle: "最終版を書き出し",
                onExport: onExportMastered,
                exportDisabled: !job.hasExistingMasteredOutput || job.isMastering,
                previewTitle: "プレビューを開く",
                onPreview: onOpenMasteredPreview,
                previewDisabled: !job.hasExistingMasteredOutput || job.isMastering,
                statusText: job.masteringStatusMessage,
                statusColor: masteringStatusColor,
                captionText: masteringCaptionText
            )
        }
    }

    private var masteringCaptionText: String {
        if job.hasExistingOutput && !job.canUseCorrectedAnalysisForMastering {
            return "補正後の解析が完了すると実行できます"
        }
        return job.isUsingCustomMasteringSettings ? "詳細設定を反映します" : job.selectedMasteringProfile.summary
    }

    private func actionButtonRow(
        primaryTitle: String,
        onPrimary: @escaping () -> Void,
        primaryDisabled: Bool,
        exportTitle: String,
        onExport: @escaping (AudioExportFormat) -> Void,
        exportDisabled: Bool,
        previewTitle: String,
        onPreview: @escaping () -> Void,
        previewDisabled: Bool,
        statusText: String,
        statusColor: Color,
        captionText: String
    ) -> some View {
        HStack(spacing: 12) {
            Button(primaryTitle, action: onPrimary)
                .disabled(primaryDisabled)

            Menu(exportTitle) {
                ForEach(AudioExportFormat.allCases) { format in
                    Button(format.menuTitle) {
                        onExport(format)
                    }
                }
            }
                .disabled(exportDisabled)

            Button(previewTitle, action: onPreview)
                .disabled(previewDisabled)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(statusText)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(statusColor)
                Text(captionText)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
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
}
