import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var job = ProcessingJob()
    @State private var preview = AudioPreviewController()
    @State private var inputSelectionID = UUID()

    private let comparisonCardColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                inputSection
                settingsSection
                outputSection
                PreviewPanelView(
                    preview: preview,
                    inputFileURL: job.inputFile,
                    correctedFileURL: job.hasExistingOutput ? job.outputFile : nil,
                    masteredFileURL: job.hasExistingMasteredOutput ? job.masteredOutputFile : nil
                )
                correctionActionSection
                masteringActionSection
                progressSection
                masteringDifferenceSection
                spectrogramSection
                metricsSection
                logSection
            }
            .padding(24)
        }
        .frame(minWidth: 1_060, minHeight: 860)
        .onChange(of: job.selectedMasteringProfile) { _, newValue in
            job.applyMasteringProfile(newValue)
        }
        .onDisappear {
            PreviewFileStore.removeAllPreviewFiles()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Veloura Lucent")
                .font(.largeTitle.bold())
            Text("補正で荒れを整えたあと、別機能のマスタリングで仕上げまで行います。")
                .foregroundStyle(.secondary)
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("入力ファイル")
                .font(.headline)

            HStack {
                Text(job.inputFile?.path(percentEncoded: false) ?? "まだ選択されていません")
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                Button("音声を選ぶ") {
                    if let url = FilePanelService.chooseAudioFile() {
                        let selectionID = beginInputSelection(for: url)
                        analyzeMetrics(for: url, target: .input, selectionID: selectionID)
                    }
                }
                .disabled(job.isProcessing || job.isMastering || job.isAnalyzingMetrics)
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("プレビュー用の一時保持")
                .font(.headline)

            outputPathRow(title: "補正後プレビュー", fileURL: job.outputFile, placeholder: "補正を実行すると一時ファイルが作られます")
            outputPathRow(title: "最終版プレビュー", fileURL: job.masteredOutputFile, placeholder: "マスタリングを実行すると一時ファイルが作られます")
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            DetailedSettingsPanel(job: job)
            analysisModeSection
        }
    }

    private func outputPathRow(title: String, fileURL: URL?, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(fileURL?.path(percentEncoded: false) ?? placeholder)
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var correctionActionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("補正")
                .font(.headline)

            actionButtonRow(
                primaryTitle: job.isProcessing ? "補正中..." : "補正を実行",
                onPrimary: startCorrectionProcessing,
                primaryDisabled: job.inputFile == nil || job.isProcessing || job.isMastering,
                exportTitle: "補正を書き出し",
                onExport: exportCorrectedAudio,
                exportDisabled: !job.hasExistingOutput || job.isProcessing,
                previewTitle: "プレビューを開く",
                onPreview: {
                    guard let outputFile = job.outputFile else { return }
                    NSWorkspace.shared.open(outputFile)
                },
                previewDisabled: !job.hasExistingOutput || job.isProcessing,
                statusText: job.statusMessage,
                statusColor: correctionStatusColor,
                captionText: job.isAnalyzingMetrics ? "比較を更新中" : "ノイズ除去は「\(job.selectedDenoiseStrength.title)」です"
            )
        }
    }

    private var analysisModeSection: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("解析モード")
                    .font(.subheadline.weight(.semibold))
                Picker("解析モード", selection: $job.selectedAnalysisMode) {
                    ForEach(AudioAnalysisMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(job.isProcessing)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("説明")
                    .font(.subheadline.weight(.semibold))
                Text(job.selectedAnalysisMode.summary)
                    .foregroundStyle(job.selectedAnalysisMode == .experimentalMetal ? .orange : .secondary)
                Text(job.selectedAnalysisMode.resolvedSummary)
                    .font(.caption)
                    .foregroundStyle(job.selectedAnalysisMode.resolvedMode == .experimentalMetal ? .orange : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var masteringActionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("マスタリング")
                .font(.headline)

            actionButtonRow(
                primaryTitle: job.isMastering ? "マスタリング中..." : "マスタリングを実行",
                onPrimary: startMasteringProcessing,
                primaryDisabled: !job.hasExistingOutput || job.isMastering || job.isProcessing,
                exportTitle: "最終版を書き出し",
                onExport: exportMasteredAudio,
                exportDisabled: !job.hasExistingMasteredOutput || job.isMastering,
                previewTitle: "プレビューを開く",
                onPreview: {
                    guard let outputFile = job.masteredOutputFile else { return }
                    NSWorkspace.shared.open(outputFile)
                },
                previewDisabled: !job.hasExistingMasteredOutput || job.isMastering,
                statusText: job.masteringStatusMessage,
                statusColor: masteringStatusColor,
                captionText: job.isUsingCustomMasteringSettings ? "詳細設定を反映します" : job.selectedMasteringProfile.summary
            )
        }
    }

    private func actionButtonRow(
        primaryTitle: String,
        onPrimary: @escaping () -> Void,
        primaryDisabled: Bool,
        exportTitle: String,
        onExport: @escaping () -> Void,
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

            Button(exportTitle, action: onExport)
                .disabled(exportDisabled)

            Button(previewTitle, action: onPreview)
                .disabled(previewDisabled)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(statusText)
                    .foregroundStyle(statusColor)
                Text(captionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            progressBlock(
                title: "補正の進行状況",
                status: job.progressLabel,
                tint: correctionStatusColor,
                value: job.progressValue,
                steps: ProcessingStep.allCases,
                activeStep: job.activeStep,
                completedSteps: job.completedSteps,
                skippedSteps: job.skippedSteps,
                failedSteps: job.failedSteps
            )

            masteringProgressBlock
        }
    }

    private func progressBlock(
        title: String,
        status: String,
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
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: value)
                .tint(tint)

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

    private var masteringProgressBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("マスタリングの進行状況")
                    .font(.headline)
                Spacer()
                Text(masteringProgressLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: masteringProgressValue)
                .tint(masteringStatusColor)

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

    private func progressBadge(title: String, isCompleted: Bool, isActive: Bool, isSkipped: Bool, isFailed: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isFailed ? "xmark.circle.fill" : isSkipped ? "minus.circle.fill" : isCompleted ? "checkmark.circle.fill" : isActive ? "dot.circle.fill" : "circle")
                .foregroundStyle(isFailed ? Color.red : isSkipped ? Color.secondary : isCompleted ? Color.green : isActive ? Color.orange : Color.secondary)
            Text(title)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isFailed ? Color.red.opacity(0.12) : isActive ? Color.orange.opacity(0.14) : isCompleted ? Color.green.opacity(0.14) : Color.secondary.opacity(isSkipped ? 0.14 : 0.08))
        )
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("数値と視覚比較")
                    .font(.headline)
                Spacer()
                if job.isAnalyzingMetrics {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let inputMetrics = job.inputMetrics {
                LazyVGrid(columns: comparisonCardColumns, alignment: .leading, spacing: 14) {
                    comparisonMetricsTable(input: inputMetrics, corrected: job.outputMetrics, mastered: job.masteredMetrics)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    comparisonBandComparisonCard(input: inputMetrics, corrected: job.outputMetrics, mastered: job.masteredMetrics)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                if let qualityReport = AudioQualityReportService.makeReport(
                        input: inputMetrics,
                        corrected: job.outputMetrics,
                        mastered: job.masteredMetrics
                ) {
                    qualityReportCard(qualityReport)
                }

                if let noiseCheckReport = NoiseCheckReportService.makeReport(
                    input: job.inputNoiseMeasurements,
                    corrected: job.outputNoiseMeasurements,
                    mastered: job.masteredNoiseMeasurements,
                    correctionSettings: job.appliedCorrectionSettings ?? job.editableCorrectionSettings,
                    settings: job.appliedMasteringSettings ?? job.editableMasteringSettings
                ) {
                    noiseCheckCard(noiseCheckReport)
                }
            } else {
                Text("音声を選ぶと、ここに入力・補正後・最終版の比較がまとめて表示されます。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func qualityReportCard(_ report: AudioQualityReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("品質チェック")
                    .font(.headline)
                Spacer()
                Text(qualityReportSeverityText(report.severity))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(qualityReportSeverityColor(report.severity))
            }

            if report.items.isEmpty {
                Text("大きな音量低下、ピーク超過、高域の増えすぎ・下がりすぎ、ステレオ幅の急変は見つかっていません。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(report.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(qualityReportSeverityColor(item.severity))
                                .frame(width: 7, height: 7)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func noiseCheckCard(_ report: NoiseCheckReport) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ノイズチェック")
                        .font(.title2.weight(.bold))
                    Text("入力、補正後、マスタリング後を実測し、ノイズ種別ごとに改善量と戻り量を判定します。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(noiseCheckSeverityText(report.severity))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(noiseCheckSeverityColor(report.severity))
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(report.rows) { row in
                    noiseCheckRow(row)
                }
            }

            if !report.recommendedActions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("聴いて気になる場合の調整候補")
                        .font(.headline)
                    ForEach(report.recommendedActions) { action in
                        noiseCheckActionCard(action)
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func noiseCheckRow(_ row: NoiseCheckRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.label)
                        .font(.title3.weight(.semibold))
                    Text(row.measurementDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(row.displayDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(row.summaryText)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(noiseCheckSeverityColor(row.severity))
            }

            noiseCheckBarLine(title: "入力", value: row.input, row: row, color: .blue)
            noiseCheckBarLine(title: "補正後", value: row.corrected, row: row, color: .green, deltaText: row.correctionEffectText, delta: row.correctionDeltaDB)
            noiseCheckBarLine(title: "最終版", value: row.mastered, row: row, color: .orange, deltaText: row.masteringEffectText, delta: row.masteringDeltaDB)

            if row.recommendedActions.isEmpty {
                Text("数値上の追加候補はありません。最終版を聴いて違和感がないか確認してください。")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func noiseCheckBarLine(
        title: String,
        value: NoiseCheckValue?,
        row: NoiseCheckRow,
        color: Color,
        deltaText: String? = nil,
        delta: Double? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(width: 72, alignment: .leading)
            GeometryReader { proxy in
                let width = proxy.size.width
                let normalized = noiseLevelRatio(value?.levelDB, row: row)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(value == nil ? 0.20 : 0.14))
                        .frame(width: value == nil ? max(2, width * normalized) : width, height: 12)
                    if value != nil {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(0.78))
                            .frame(width: max(3, width * normalized), height: 12)
                    }
                }
            }
            .frame(height: 14)
            .frame(maxWidth: .infinity)
            Text(value.map { formatNoiseValue($0) } ?? "--")
                .font(.body.monospacedDigit().weight(.semibold))
                .frame(width: 120, alignment: .trailing)
            if let deltaText {
                Text(deltaText)
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(noiseDeltaColor(delta, lowerIsBetter: true))
                    .frame(width: 190, alignment: .leading)
            } else {
                Text("")
                    .frame(width: 190, alignment: .leading)
            }
        }
    }

    private func noiseCheckActionCard(_ action: NoiseCheckAction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(action.title)
                    .font(.headline.weight(.semibold))
                Spacer()
                Text("\(action.currentValue) → \(action.recommendedValue)（\(action.changeValue)）")
                    .font(.headline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Text(action.reason)
                .font(.body)
                .foregroundStyle(.secondary)
            Text(action.expectedEffect)
                .font(.body)
                .foregroundStyle(.secondary)
            Text(action.caution)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func noiseLevelRatio(_ value: Double?, row: NoiseCheckRow) -> Double {
        row.displayScale.ratio(for: value)
    }

    private func formatNoiseValue(_ value: NoiseCheckValue) -> String {
        String(format: "%.1f %@", value.levelDB, value.unitLabel)
    }

    private func formatNoiseDelta(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: value >= 0 ? "+%.1f dB" : "%.1f dB", value)
    }

    private func noiseDeltaColor(_ value: Double?, lowerIsBetter: Bool) -> Color {
        guard let value, abs(value) >= 0.5 else { return .secondary }
        if lowerIsBetter {
            return value < 0 ? .green : .orange
        }
        return value > 0 ? .orange : .green
    }

    private func noiseCheckSeverityText(_ severity: NoiseCheckSeverity) -> String {
        switch severity {
        case .low:
            return "目立つ問題なし"
        case .caution:
            return "少し目立つ"
        case .warning:
            return "目立つ"
        }
    }

    private func noiseCheckSeverityColor(_ severity: NoiseCheckSeverity) -> Color {
        switch severity {
        case .low:
            return .green
        case .caution:
            return .orange
        case .warning:
            return .red
        }
    }

    private func denoiseEffectCard(_ report: DenoiseEffectReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ノイズ除去後の高域変化")
                    .font(.headline)
                Text("左に伸びるほど、その帯域の音量やチラつきが下がっています。補正後全体ではなく、ノイズ除去工程だけを見ます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                denoiseEffectRow(title: "10-16kHzチラつき", value: report.shimmerFlickerChangeDB, limit: 12)
                denoiseEffectRow(title: "12kHz以上", value: report.hf12ChangeDB, limit: 12)
                denoiseEffectRow(title: "16kHz以上", value: report.hf16ChangeDB, limit: 12)
                denoiseEffectRow(title: "18kHz以上", value: report.hf18ChangeDB, limit: 12)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func denoiseEffectRow(title: String, value: Double, limit: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(String(format: "%+.1f dB", value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(value <= 0 ? .green : .orange)
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let center = width / 2
                let ratio = min(abs(value) / limit, 1)
                let barWidth = center * ratio

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.14))
                        .frame(height: 6)

                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 1, height: 10)
                        .offset(x: center)

                    if ratio > 0.001 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(value <= 0 ? Color.green.opacity(0.78) : Color.orange.opacity(0.78))
                            .frame(width: max(2, barWidth), height: 6)
                            .offset(x: value <= 0 ? center - max(2, barWidth) : center)
                    }
                }
            }
            .frame(height: 10)
        }
    }

    private func qualityReportSeverityText(_ severity: AudioQualityReportSeverity) -> String {
        switch severity {
        case .info:
            return "OK"
        case .caution:
            return "注意"
        case .warning:
            return "警告"
        }
    }

    private func qualityReportSeverityColor(_ severity: AudioQualityReportSeverity) -> Color {
        switch severity {
        case .info:
            return .green
        case .caution:
            return .orange
        case .warning:
            return .red
        }
    }

    private var masteringDifferenceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("音源変化の比較")
                    .font(.headline)
                Spacer()
                Text("入力 -> 補正後 -> 最終版")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let corrected = job.outputMetrics, let mastered = job.masteredMetrics {
                let stages = comparisonStages(
                    input: job.inputMetrics,
                    corrected: corrected,
                    mastered: mastered
                )
                HStack(alignment: .top, spacing: 14) {
                    comparisonDirectionSummaryCard(input: job.inputMetrics, corrected: corrected, mastered: mastered)
                    comparisonBalanceCurveCard(stages: stages)
                }

                LazyVGrid(columns: comparisonCardColumns, alignment: .leading, spacing: 14) {
                    shortTermLoudnessCard(stages: stages)
                    spectrumComparisonCard(input: job.inputMetrics, corrected: corrected, mastered: mastered)
                    dynamicsTrendCard(stages: stages)
                    correlationMeterCard(input: job.inputMetrics, corrected: corrected, mastered: mastered)
                }

                Text("左で実測差分の要点、右で帯域の触り方を見比べられます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("最終版の比較は、マスタリングを実行すると表示されます。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func comparisonDirectionSummaryCard(
        input: AudioMetricSnapshot?,
        corrected: AudioMetricSnapshot,
        mastered: AudioMetricSnapshot
    ) -> some View {
        let rows = comparisonDirectionSummaryRows(input: input, corrected: corrected, mastered: mastered)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("仕上がりの方向")
                    .font(.headline)
                Spacer()
                termHelpButton(
                    title: "仕上がりの方向",
                    reading: "しあがりのほうこう",
                    description: "点数化せず、入力から最終版、補正後から最終版の実測差分を見ます。"
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(row.finalValue)
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(row.tint)
                        }
                        HStack(spacing: 10) {
                            directionDeltaChip(title: "入力差", value: row.inputDeltaText, tint: row.inputTint)
                            directionDeltaChip(title: "仕上げ差", value: row.masteringDeltaText, tint: row.masteringTint)
                        }
                        Text(row.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(row.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 500, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func directionDeltaChip(title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.10), in: Capsule())
    }

    private func shortTermLoudnessCard(stages: [ComparisonStageMetrics]) -> some View {
        let points = timelinePoints(stages: stages, values: { $0.shortTermLoudness.map { ($0.time, $0.levelDB) } })
        let values = points.map(\.value)
        let minValue = floor((values.min() ?? -36) / 2) * 2 - 1
        let maxValue = ceil((values.max() ?? -12) / 2) * 2 + 1

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("短期ラウドネス")
                    .font(.headline)
                Spacer()
                termHelpButton(
                    title: "短期ラウドネス",
                    reading: "たんきらうどねす",
                    description: "場面ごとの音量感です。アプリ内で同じ基準にそろえて測ります。線が近づきすぎると、抑揚が少なくなっている可能性があります。"
                )
            }

            timelineLineChart(points: points, yTitle: "音量感", yDomain: minValue ... maxValue)
                .frame(height: 260)

            chartLegend(stages: stages)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func dynamicsTrendCard(stages: [ComparisonStageMetrics]) -> some View {
        let points = timelinePoints(stages: stages, values: { $0.dynamics.map { ($0.time, $0.crestFactorDB) } })
        let values = points.map(\.value)
        let minValue = max(0, floor((values.min() ?? 0) / 2) * 2 - 1)
        let maxValue = ceil((values.max() ?? 12) / 2) * 2 + 1

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ダイナミクス推移")
                    .font(.headline)
                Spacer()
                termHelpButton(
                    title: "ダイナミクス推移",
                    reading: "だいなみくすすいい",
                    description: "音の山と平均の差です。小さくなりすぎると、音が押し固められている可能性があります。"
                )
            }

            timelineLineChart(points: points, yTitle: "Peak - RMS", yDomain: minValue ... maxValue)
                .frame(height: 260)

            chartLegend(stages: stages)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func spectrumComparisonCard(input: AudioMetricSnapshot?, corrected: AudioMetricSnapshot, mastered: AudioMetricSnapshot) -> some View {
        let spectrumPoints = spectrumComparisonPoints(input: input, corrected: corrected, mastered: mastered)
        let diffPoints = spectrumDeltaPoints(input: input, corrected: corrected, mastered: mastered)
        let spectrumValues = spectrumPoints.map(\.levelDB)
        let diffValues = diffPoints.map(\.deltaDB)
        let spectrumMin = floor((spectrumValues.min() ?? -60) / 3) * 3 - 2
        let spectrumMax = ceil((spectrumValues.max() ?? -18) / 3) * 3 + 2
        let diffMin = min(floor((diffValues.min() ?? -3) / 1.5) * 1.5 - 0.5, -0.5)
        let diffMax = max(ceil((diffValues.max() ?? 3) / 1.5) * 1.5 + 0.5, 0.5)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("平均スペクトル比較")
                    .font(.headline)
                Spacer()
                termHelpButton(
                    title: "平均スペクトル比較",
                    reading: "へいきんすぺくとるひかく",
                    description: "入力、補正後、最終版の周波数ごとの相対量を重ね、下段で補正と仕上げの差分を見ます。絶対音量ではなく、形の変化を見る表示です。"
                )
            }

            averageSpectrumChart(points: spectrumPoints, yDomain: spectrumMin ... spectrumMax)
                .frame(height: 210)

            spectrumDeltaChart(points: diffPoints, yDomain: diffMin ... diffMax)
                .frame(height: 150)

            HStack(spacing: 14) {
                if input != nil {
                    legendChip(color: .blue, label: "入力", dashed: true)
                }
                legendChip(color: .green, label: "補正後", dashed: false)
                legendChip(color: .orange, label: "最終版", dashed: false)
                if input != nil {
                    legendChip(color: .green, label: "差分: 補正後 - 入力", dashed: true)
                }
                legendChip(color: .orange, label: "差分: 最終版 - 補正後", dashed: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 500, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func correlationMeterCard(input: AudioMetricSnapshot?, corrected: AudioMetricSnapshot, mastered: AudioMetricSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("相関メーター")
                    .font(.headline)
                Spacer()
                termHelpButton(
                    title: "相関メーター",
                    reading: "そうかんめーたー",
                    description: "左右の音がどれくらい同じ向きで鳴っているかを見る指標です。0より左へ寄るほど、モノラル再生で音が痩せる可能性があります。"
                )
            }

            if let input {
                correlationMeterRow(title: "入力", value: input.stereoCorrelation, tint: .blue)
            }
            correlationMeterRow(title: "補正後", value: corrected.stereoCorrelation, tint: .green)
            correlationMeterRow(title: "最終版", value: mastered.stereoCorrelation, tint: .orange)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("-1")
                    Spacer()
                    Text("0")
                    Spacer()
                    Text("+1")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                Text("右側にあるほどモノラル互換性が高く、左側に入ると位相打ち消しに注意です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func correlationMeterRow(title: String, value: Double, tint: Color) -> some View {
        let clampedValue = max(-1, min(1, value))
        let normalized = (clampedValue + 1) * 0.5

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%+.2f", clampedValue))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(correlationColor(for: clampedValue, tint: tint))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.12))

                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 1)
                        .offset(x: proxy.size.width * 0.5)

                    Capsule()
                        .fill(correlationColor(for: clampedValue, tint: tint))
                        .frame(width: 12, height: 24)
                        .offset(x: max(0, min(proxy.size.width - 12, proxy.size.width * normalized - 6)))
                }
            }
            .frame(height: 24)
        }
    }

    private func correlationColor(for value: Double, tint: Color) -> Color {
        if value < 0 {
            return .red
        }
        if value < 0.25 {
            return .orange
        }
        return tint
    }

    private func comparisonBalanceCurveCard(stages: [ComparisonStageMetrics]) -> some View {
        let points = comparisonCurvePoints(stages: stages)
        let values = points.map(\.value)
        let minValue = floor((values.min() ?? -36) / 2) * 2 - 2
        let maxValue = ceil((values.max() ?? -12) / 2) * 2 + 2

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("周波数バランス")
                    .font(.headline)
                Spacer()
                termHelpButton(
                    title: "周波数バランスの見方",
                    reading: "しゅうはすうばらんすのみかた",
                    description: "青が入力、緑が補正後、オレンジが最終版です。同じ帯域で線が上下するほど、その帯域の量が変わっています。"
                )
            }

            Chart(points) { point in
                LineMark(
                    x: .value("帯域順", point.order),
                    y: .value("レベル", point.value)
                )
                .foregroundStyle(by: .value("系列", point.series))
                .interpolationMethod(.catmullRom)
                .lineStyle(.init(lineWidth: 3))

                PointMark(
                    x: .value("帯域順", point.order),
                    y: .value("レベル", point.value)
                )
                .foregroundStyle(by: .value("系列", point.series))
                .symbolSize(48)
            }
            .chartLegend(.hidden)
            .chartForegroundStyleScale([
                "入力": Color.blue,
                "補正後": Color.green,
                "最終版": Color.orange
            ])
            .chartXScale(domain: -0.2 ... Double(AudioBandCatalog.comparisonBands.count - 1) + 0.35)
            .chartYScale(domain: minValue ... maxValue)
            .chartXAxis {
                AxisMarks(values: Array(0..<AudioBandCatalog.comparisonBands.count)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let index = value.as(Int.self), AudioBandCatalog.comparisonBands.indices.contains(index) {
                            Text(AudioBandCatalog.comparisonBands[index].label)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(String(format: "%.0f 相対dB", number))
                        }
                    }
                }
            }
            .frame(height: 390)

            chartLegend(stages: stages)
            termHelpGrid(items: comparisonBandTermDefinitions)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 500, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func chartLegend(stages: [ComparisonStageMetrics]) -> some View {
        HStack(spacing: 14) {
            ForEach(stages) { stage in
                legendChip(color: stage.color, label: stage.label, dashed: stage.id == "input")
            }
        }
    }

    private func legendChip(color: Color, label: String, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            if dashed {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .foregroundStyle(color)
                    .frame(width: 16, height: 8)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func comparisonStages(
        input: AudioMetricSnapshot?,
        corrected: AudioMetricSnapshot?,
        mastered: AudioMetricSnapshot?
    ) -> [ComparisonStageMetrics] {
        var stages: [ComparisonStageMetrics] = []
        if let input {
            stages.append(ComparisonStageMetrics(id: "input", label: "入力", color: .blue, metrics: input))
        }
        if let corrected {
            stages.append(ComparisonStageMetrics(id: "corrected", label: "補正後", color: .green, metrics: corrected))
        }
        if let mastered {
            stages.append(ComparisonStageMetrics(id: "mastered", label: "最終版", color: .orange, metrics: mastered))
        }
        return stages
    }

    private func comparisonDirectionSummaryRows(
        input: AudioMetricSnapshot?,
        corrected: AudioMetricSnapshot,
        mastered: AudioMetricSnapshot
    ) -> [DirectionSummaryRow] {
        let inputReference = input ?? corrected
        return [
            directionRow(
                id: "loudness",
                title: "ラウドネス",
                finalValue: formattedValue(mastered.integratedLoudnessLUFS, format: .lufs),
                inputDelta: mastered.integratedLoudnessLUFS - inputReference.integratedLoudnessLUFS,
                masteringDelta: mastered.integratedLoudnessLUFS - corrected.integratedLoudnessLUFS,
                deltaFormat: .lufs,
                positiveColor: .orange,
                negativeColor: .secondary,
                detail: "最終版の平均的な音量感です。上がりすぎると聴き疲れしやすくなります。"
            ),
            directionRow(
                id: "peak",
                title: "トゥルーピーク",
                finalValue: formattedValue(mastered.truePeakDBFS, format: .dBFS),
                inputDelta: mastered.truePeakDBFS - inputReference.truePeakDBFS,
                masteringDelta: mastered.truePeakDBFS - corrected.truePeakDBFS,
                deltaFormat: .dB,
                positiveColor: mastered.truePeakDBFS > -0.3 ? .red : .orange,
                negativeColor: .green,
                detail: "最終版の最大ピークです。0 dBFS に近すぎると歪みやすくなります。"
            ),
            directionRow(
                id: "dynamics",
                title: "ダイナミクス",
                finalValue: formattedValue(mastered.crestFactorDB, format: .dB),
                inputDelta: mastered.crestFactorDB - inputReference.crestFactorDB,
                masteringDelta: mastered.crestFactorDB - corrected.crestFactorDB,
                deltaFormat: .dB,
                positiveColor: .green,
                negativeColor: .orange,
                detail: "音の山と平均の差です。下がりすぎると平坦に聞こえやすくなります。"
            ),
            directionBandRow(
                id: "sparkle",
                title: "煌びやかさ",
                bandID: "sparkle",
                input: inputReference,
                corrected: corrected,
                mastered: mastered,
                detail: "8kHz〜12kHz の実測値です。抜け感やきらめきに関わります。"
            ),
            directionBandRow(
                id: "air",
                title: "空気感",
                bandID: "air",
                input: inputReference,
                corrected: corrected,
                mastered: mastered,
                detail: "12kHz〜16kHz の実測値です。息感や空気の伸びに関わります。"
            ),
            directionBandRow(
                id: "ultraAir",
                title: "超高域",
                bandID: "ultraAir",
                input: inputReference,
                corrected: corrected,
                mastered: mastered,
                detail: "16kHz〜20kHz の実測値です。空気感の最上部と超高域の伸びに関わります。"
            ),
            directionBandRow(
                id: "mud",
                title: "こもり",
                bandID: "mud",
                input: inputReference,
                corrected: corrected,
                mastered: mastered,
                positiveIsBetter: false,
                detail: "300Hz〜1kHz の実測値です。増えると暗さやこもりに聞こえやすい帯域です。"
            )
        ]
    }

    private func directionBandRow(
        id: String,
        title: String,
        bandID: String,
        input: AudioMetricSnapshot,
        corrected: AudioMetricSnapshot,
        mastered: AudioMetricSnapshot,
        positiveIsBetter: Bool = true,
        detail: String
    ) -> DirectionSummaryRow {
        let inputValue = comparisonBandValue(input, id: bandID) ?? -120
        let correctedValue = comparisonBandValue(corrected, id: bandID) ?? inputValue
        let masteredValue = comparisonBandValue(mastered, id: bandID) ?? correctedValue
        return directionRow(
            id: id,
            title: title,
            finalValue: formattedValue(masteredValue, format: .dB),
            inputDelta: masteredValue - inputValue,
            masteringDelta: masteredValue - correctedValue,
            deltaFormat: .dB,
            positiveColor: positiveIsBetter ? .green : .orange,
            negativeColor: positiveIsBetter ? .orange : .green,
            detail: detail
        )
    }

    private func directionRow(
        id: String,
        title: String,
        finalValue: String,
        inputDelta: Double,
        masteringDelta: Double,
        deltaFormat: MetricFormat,
        positiveColor: Color,
        negativeColor: Color,
        detail: String
    ) -> DirectionSummaryRow {
        DirectionSummaryRow(
            id: id,
            title: title,
            finalValue: finalValue,
            inputDeltaText: formattedDelta(inputDelta, format: deltaFormat),
            masteringDeltaText: formattedDelta(masteringDelta, format: deltaFormat),
            inputTint: inputDelta >= 0 ? positiveColor : negativeColor,
            masteringTint: masteringDelta >= 0 ? positiveColor : negativeColor,
            tint: abs(masteringDelta) >= 1.5 ? (masteringDelta >= 0 ? positiveColor : negativeColor) : .secondary,
            detail: detail
        )
    }

    private func comparisonCurvePoints(stages: [ComparisonStageMetrics]) -> [MasteringCurvePoint] {
        AudioBandCatalog.comparisonBands.enumerated().flatMap { index, band in
            stages.map { stage in
                let value = stage.metrics.bandEnergies.first { $0.id == band.id }?.levelDB ?? -120
                return MasteringCurvePoint(order: index, label: band.label, series: stage.label, value: value)
            }
        }
    }

    private func timelinePoints(
        stages: [ComparisonStageMetrics],
        values: (AudioMetricSnapshot) -> [(time: Double, value: Double)]
    ) -> [TimelineCurvePoint] {
        stages.flatMap { stage in
            values(stage.metrics).enumerated().map { index, point in
                TimelineCurvePoint(
                    id: "\(stage.id)-\(index)",
                    time: point.time,
                    series: stage.label,
                    value: point.value
                )
            }
        }
    }

    private func timelineLineChart(points: [TimelineCurvePoint], yTitle: String, yDomain: ClosedRange<Double>) -> some View {
        Chart(points) { point in
            LineMark(
                x: .value("時間", point.time),
                y: .value(yTitle, point.value)
            )
            .foregroundStyle(by: .value("系列", point.series))
            .interpolationMethod(.catmullRom)
            .lineStyle(.init(lineWidth: 3))
        }
        .chartLegend(.hidden)
        .chartForegroundStyleScale([
            "入力": Color.blue,
            "補正後": Color.green,
            "最終版": Color.orange
        ])
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(String(format: "%.0fs", seconds))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(String(format: "%.0f", number))
                    }
                }
            }
        }
    }

    private func averageSpectrumChart(points: [SpectrumCurvePoint], yDomain: ClosedRange<Double>) -> some View {
        Chart {
            RectangleMark(
                xStart: .value("注目帯域開始", 8_000),
                xEnd: .value("注目帯域終了", 12_000),
                yStart: .value("下限", yDomain.lowerBound),
                yEnd: .value("上限", yDomain.upperBound)
            )
            .foregroundStyle(Color.orange.opacity(0.08))

            ForEach(points) { point in
                LineMark(
                    x: .value("周波数", point.frequencyHz),
                    y: .value("レベル", point.levelDB)
                )
                .foregroundStyle(by: .value("系列", point.series))
                .interpolationMethod(.catmullRom)
                .lineStyle(.init(lineWidth: 3))
            }
        }
        .chartLegend(.hidden)
        .chartForegroundStyleScale([
            "入力": Color.blue,
            "補正後": Color.green,
            "最終版": Color.orange
        ])
        .chartXScale(domain: 80 ... 20_000, type: .log)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            spectrumAxisMarks()
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(String(format: "%.0f 相対dB", number))
                    }
                }
            }
        }
    }

    private func spectrumDeltaChart(points: [SpectrumDeltaPoint], yDomain: ClosedRange<Double>) -> some View {
        Chart {
            RectangleMark(
                xStart: .value("注目帯域開始", 8_000),
                xEnd: .value("注目帯域終了", 12_000),
                yStart: .value("下限", yDomain.lowerBound),
                yEnd: .value("上限", yDomain.upperBound)
            )
            .foregroundStyle(Color.orange.opacity(0.08))

            RuleMark(y: .value("基準", 0))
                .foregroundStyle(Color.secondary.opacity(0.35))

            ForEach(points) { point in
                LineMark(
                    x: .value("周波数", point.frequencyHz),
                    y: .value("差分", point.deltaDB)
                )
                .foregroundStyle(by: .value("系列", point.series))
                .interpolationMethod(.catmullRom)
                .lineStyle(.init(lineWidth: 2.6, dash: [7, 4]))
            }
        }
        .chartLegend(.hidden)
        .chartForegroundStyleScale([
            "補正後 - 入力": Color.green,
            "最終版 - 補正後": Color.orange
        ])
        .chartXScale(domain: 80 ... 20_000, type: .log)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            spectrumAxisMarks()
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(String(format: "%+.0f dB", number))
                    }
                }
            }
        }
    }

    private func spectrumAxisMarks() -> some AxisContent {
        AxisMarks(values: [100, 1_000, 4_000, 6_000, 10_000, 20_000]) { value in
            AxisGridLine()
            AxisTick()
            AxisValueLabel {
                if let frequency = value.as(Double.self) {
                    Text(frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))")
                }
            }
        }
    }

    private func spectrumComparisonPoints(input: AudioMetricSnapshot?, corrected: AudioMetricSnapshot, mastered: AudioMetricSnapshot) -> [SpectrumCurvePoint] {
        let inputPoints = input?.averageSpectrum.map {
            SpectrumCurvePoint(
                id: "input-\($0.id)",
                frequencyHz: $0.frequencyHz,
                series: "入力",
                levelDB: $0.levelDB
            )
        } ?? []

        return inputPoints + corrected.averageSpectrum.map {
            SpectrumCurvePoint(
                id: "corrected-\($0.id)",
                frequencyHz: $0.frequencyHz,
                series: "補正後",
                levelDB: $0.levelDB
            )
        } + mastered.averageSpectrum.map {
            SpectrumCurvePoint(
                id: "mastered-\($0.id)",
                frequencyHz: $0.frequencyHz,
                series: "最終版",
                levelDB: $0.levelDB
            )
        }
    }

    private func spectrumDeltaPoints(input: AudioMetricSnapshot?, corrected: AudioMetricSnapshot, mastered: AudioMetricSnapshot) -> [SpectrumDeltaPoint] {
        let correctedMap = Dictionary(uniqueKeysWithValues: corrected.averageSpectrum.map { ($0.id, $0) })
        let masteredMap = Dictionary(uniqueKeysWithValues: mastered.averageSpectrum.map { ($0.id, $0) })

        let correctionDelta = input?.averageSpectrum.compactMap { inputPoint -> SpectrumDeltaPoint? in
            guard let correctedPoint = correctedMap[inputPoint.id] else { return nil }
            return SpectrumDeltaPoint(
                id: "corrected-input-\(inputPoint.id)",
                frequencyHz: inputPoint.frequencyHz,
                series: "補正後 - 入力",
                deltaDB: correctedPoint.levelDB - inputPoint.levelDB
            )
        } ?? []

        let masteringDelta = corrected.averageSpectrum.compactMap { correctedPoint -> SpectrumDeltaPoint? in
            guard let masteredPoint = masteredMap[correctedPoint.id] else { return nil }
            return SpectrumDeltaPoint(
                id: "mastered-corrected-\(correctedPoint.id)",
                frequencyHz: correctedPoint.frequencyHz,
                series: "最終版 - 補正後",
                deltaDB: masteredPoint.levelDB - correctedPoint.levelDB
            )
        }

        return correctionDelta + masteringDelta
    }

    private func comparisonMetricsTable(
        input: AudioMetricSnapshot,
        corrected: AudioMetricSnapshot?,
        mastered: AudioMetricSnapshot?
    ) -> some View {
        let rows = comparisonMetricRows(input: input, corrected: corrected, mastered: mastered)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("主な数値")
                    .font(.title3.weight(.bold))
                Spacer()
                termHelpButton(
                    title: "主な数値の見方",
                    reading: "おもなすうちのみかた",
                    description: "入力、補正後、最終版を同じ尺度で並べています。オレンジ側に近づくほど、最終仕上げでの変化が大きいです。"
                )
            }

            GeometryReader { proxy in
                let layout = metricTableLayout(for: proxy.size.width)
                let rowCount = rows.count + 1
                let dividerTotal = CGFloat(rowCount - 1)
                let usableHeight = max(proxy.size.height - dividerTotal, 0)
                let rowHeight = max(42, usableHeight / CGFloat(rowCount))

                VStack(spacing: 0) {
                    metricTableHeader(layout: layout)
                        .frame(height: rowHeight, alignment: .center)
                    Divider()

                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        metricTableValueRow(row, layout: layout)
                            .frame(height: rowHeight, alignment: .center)

                        if index < rows.count - 1 {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 560, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func comparisonBandComparisonCard(
        input: AudioMetricSnapshot,
        corrected: AudioMetricSnapshot?,
        mastered: AudioMetricSnapshot?
    ) -> some View {
        let correctedMap = Dictionary(uniqueKeysWithValues: (corrected?.bandEnergies ?? []).map { ($0.id, $0) })
        let masteredMap = Dictionary(uniqueKeysWithValues: (mastered?.bandEnergies ?? []).map { ($0.id, $0) })
        let rows = input.bandEnergies.map { inputMetric in
            ComparisonBandRow(
                id: inputMetric.id,
                label: inputMetric.label,
                rangeDescription: inputMetric.rangeDescription,
                input: inputMetric.levelDB,
                corrected: correctedMap[inputMetric.id]?.levelDB,
                mastered: masteredMap[inputMetric.id]?.levelDB
            )
        }

        let allValues = rows.flatMap { row in
            [row.input, row.corrected ?? row.input, row.mastered ?? row.corrected ?? row.input]
        }
        let maxLevel = (allValues.max() ?? 0) + 3
        let minLevel = min((allValues.min() ?? -60), -40) - 3

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("周波数バランス詳細")
                    .font(.title3.weight(.bold))
                Spacer()
                termHelpButton(
                    title: "周波数バランス詳細",
                    reading: "しゅうはすうばらんすしょうさい",
                    description: "各帯域の量を、入力・補正後・最終版で並べています。右側の差分は、補正段と最終仕上げ段でどれだけ変わったかを示します。"
                )
            }

            ForEach(rows) { row in
                comparisonBandRow(row, minLevel: minLevel, maxLevel: maxLevel)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 560, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func comparisonBandRow(_ row: ComparisonBandRow, minLevel: Double, maxLevel: Double) -> some View {
        let correctionDelta = row.corrected.map { $0 - row.input }
        let masteringDelta = {
            guard let corrected = row.corrected, let mastered = row.mastered else { return Optional<Double>.none }
            return mastered - corrected
        }()

        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                termLabel(item: termDefinition(for: row.id, from: comparisonBandTermDefinitions))
                Text(row.rangeDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 120, alignment: .leading)

            VStack(spacing: 8) {
                comparisonBandBar(title: "入力", value: row.input, minLevel: minLevel, maxLevel: maxLevel, tint: .blue)
                comparisonBandBar(title: "補正後", value: row.corrected, minLevel: minLevel, maxLevel: maxLevel, tint: .green)
                comparisonBandBar(title: "最終版", value: row.mastered, minLevel: minLevel, maxLevel: maxLevel, tint: .orange)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .trailing, spacing: 8) {
                Text("差分")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                deltaPairLine(title: "補正", value: correctionDelta)
                deltaPairLine(title: "仕上", value: masteringDelta)
            }
            .frame(width: 110, alignment: .trailing)
        }
    }

    private func comparisonBandBar(title: String, value: Double?, minLevel: Double, maxLevel: Double, tint: Color) -> some View {
        let normalized = value.map { max(0, min(1, ($0 - minLevel) / max(maxLevel - minLevel, 1))) } ?? 0

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value.map { formattedValue($0, format: .dB) } ?? "--")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(tint.gradient)
                        .frame(width: proxy.size.width * normalized)
                }
            }
            .frame(height: 10)
        }
    }

    private func deltaPairLine(title: String, value: Double?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value.map { formattedDelta($0, format: .dB) } ?? "--")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(deltaChipColor(for: value))
        }
    }

    private func metricTableHeader(layout: MetricTableLayout) -> some View {
        HStack(spacing: 0) {
            Text("項目")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: layout.labelWidth, alignment: .leading)
            Text("入力")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: layout.valueWidth, alignment: .leading)
            Text("補正後")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: layout.valueWidth, alignment: .leading)
            Text("最終版")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: layout.valueWidth, alignment: .leading)
        }
    }

    private func metricTableValueRow(_ row: MetricTableRow, layout: MetricTableLayout) -> some View {
        HStack(spacing: 0) {
            termLabel(item: row.item)
                .frame(width: layout.labelWidth, alignment: .leading)
            metricsTableValue(row.input, format: row.format, tint: .blue)
                .frame(width: layout.valueWidth, alignment: .leading)
            metricsTableValue(row.corrected, format: row.format, tint: .green)
                .frame(width: layout.valueWidth, alignment: .leading)
            metricsTableValue(row.mastered, format: row.format, tint: .orange)
                .frame(width: layout.valueWidth, alignment: .leading)
        }
    }

    private func metricsTableValue(_ value: Double?, format: MetricFormat, tint: Color) -> some View {
        Text(value.map { formattedValue($0, format: format) } ?? "--")
            .font(.title3.monospacedDigit().weight(.semibold))
            .foregroundStyle(value == nil ? .secondary : tint)
    }

    private func comparisonMetricRows(
        input: AudioMetricSnapshot,
        corrected: AudioMetricSnapshot?,
        mastered: AudioMetricSnapshot?
    ) -> [MetricTableRow] {
        [
            MetricTableRow(item: mainMetricDefinitions[0], input: input.integratedLoudnessLUFS, corrected: corrected?.integratedLoudnessLUFS, mastered: mastered?.integratedLoudnessLUFS, format: .lufs),
            MetricTableRow(item: mainMetricDefinitions[1], input: input.truePeakDBFS, corrected: corrected?.truePeakDBFS, mastered: mastered?.truePeakDBFS, format: .dBFS),
            MetricTableRow(item: mainMetricDefinitions[2], input: input.stereoWidth, corrected: corrected?.stereoWidth, mastered: mastered?.stereoWidth, format: .ratio(2)),
            MetricTableRow(item: mainMetricDefinitions[3], input: input.harshnessScore, corrected: corrected?.harshnessScore, mastered: mastered?.harshnessScore, format: .score(2)),
            MetricTableRow(item: mainMetricDefinitions[4], input: input.crestFactorDB, corrected: corrected?.crestFactorDB, mastered: mastered?.crestFactorDB, format: .dB),
            MetricTableRow(item: mainMetricDefinitions[5], input: input.loudnessRangeLU, corrected: corrected?.loudnessRangeLU, mastered: mastered?.loudnessRangeLU, format: .lu),
        ] + comparisonBandTermDefinitions.map { definition in
            MetricTableRow(
                item: definition,
                input: comparisonBandValue(input, id: definition.id),
                corrected: corrected.flatMap { comparisonBandValue($0, id: definition.id) },
                mastered: mastered.flatMap { comparisonBandValue($0, id: definition.id) },
                format: .dB
            )
        }
    }

    private func metricTableLayout(for width: CGFloat) -> MetricTableLayout {
        let labelWidth = max(165, width * 0.30)
        let valueWidth = max(110, (width - labelWidth) / 3)
        return MetricTableLayout(labelWidth: labelWidth, valueWidth: valueWidth)
    }

    private func comparisonBandValue(_ metrics: AudioMetricSnapshot, id: String) -> Double? {
        metrics.bandEnergies.first { $0.id == id }?.levelDB
    }

    private func inputBandValue(_ metrics: AudioMetricSnapshot, id: String) -> Double? {
        metrics.masteringBandEnergies.first { $0.id == id }?.levelDB
    }

    private func termLabel(item: TermDefinition) -> some View {
        HStack(spacing: 6) {
            Text(item.label)
                .font(.title3.weight(.semibold))
            termHelpButton(title: item.label, reading: item.reading, description: item.description)
        }
    }

    private func termHelpButton(title: String, reading: String, description: String) -> some View {
        TermHelpButton(title: title, reading: reading, description: description)
    }

    private func termHelpGrid(items: [TermDefinition]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("用語ガイド")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    termLabel(item: item)
                }
            }
        }
    }

    private func termDefinition(for id: String, from items: [TermDefinition]) -> TermDefinition {
        items.first { $0.id == id } ?? TermDefinition(id: id, label: id, reading: id, description: "")
    }

    private var radarTermDefinitions: [TermDefinition] {
        [
            TermDefinition(id: "loudness", label: "音量", reading: "おんりょう", description: "曲全体の平均的な大きさです。LUFS、True Peak、LRA と同じ測定サービスでそろえて測ります。"),
            TermDefinition(id: "truePeak", label: "トゥルーピーク", reading: "とぅるーぴーく", description: "波形の本当の最大ピークです。上がりすぎると歪みやすくなります。"),
            TermDefinition(id: "clarity", label: "明瞭度", reading: "めいりょうど", description: "中低域のこもりと高域の耳障りさを合わせて見た、聞き取りやすさの目安です。"),
            TermDefinition(id: "stereoWidth", label: "ステレオ幅", reading: "すてれおはば", description: "左右への広がり具合です。大きいほど広く感じやすいです。"),
            TermDefinition(id: "highBalance", label: "高域バランス", reading: "こういきばらんす", description: "高い帯域の量感です。上がるほど明るく抜けた印象になりやすいです。")
        ]
    }

    private var bandTermDefinitions: [TermDefinition] {
        [
            TermDefinition(id: "low", label: "低域", reading: "ていいき", description: "20Hz〜180Hz 付近です。キックやベースの土台になる帯域です。"),
            TermDefinition(id: "lowMid", label: "中低域", reading: "ちゅうていいき", description: "180Hz〜500Hz 付近です。増えすぎるとこもりや重さとして感じやすい帯域です。"),
            TermDefinition(id: "presence", label: "プレゼンス帯域", reading: "ぷれぜんすたいいき", description: "2.5kHz〜5.5kHz 付近です。声や主旋律の前に出る感じに関わる帯域です。"),
            TermDefinition(id: "air", label: "エアー帯域", reading: "えあーたいいき", description: "10kHz〜20kHz 付近です。空気感や高域の伸びに関わる帯域です。")
        ]
    }

    private var comparisonBandTermDefinitions: [TermDefinition] {
        [
            TermDefinition(id: "rumble", label: "低域ノイズ", reading: "ていいきのいず", description: "20Hz〜150Hz です。不要な低音のゴロゴロ感を見ます。"),
            TermDefinition(id: "warmth", label: "太さ", reading: "ふとさ", description: "150Hz〜300Hz です。音の厚みやふくらみに関わります。"),
            TermDefinition(id: "mud", label: "こもり", reading: "こもり", description: "300Hz〜1kHz です。増えると暗さやこもりに聞こえやすい帯域です。"),
            TermDefinition(id: "core", label: "声の芯", reading: "こえのしん", description: "1kHz〜4kHz です。声や主旋律の中心に関わります。"),
            TermDefinition(id: "presence", label: "刺さり", reading: "ささり", description: "4kHz〜8kHz です。明瞭さ、サ行、耳に痛い成分を見ます。"),
            TermDefinition(id: "sparkle", label: "煌びやかさ", reading: "きらびやかさ", description: "8kHz〜12kHz です。抜け感やきらめきに関わります。"),
            TermDefinition(id: "air", label: "空気感", reading: "くうきかん", description: "12kHz〜16kHz です。息感や空気の伸びに関わります。"),
            TermDefinition(id: "ultraAir", label: "超高域", reading: "ちょうこういき", description: "16kHz〜20kHz です。高域ノイズや空気の最上部を見ます。")
        ]
    }

    private var mainMetricDefinitions: [TermDefinition] {
        [
            radarTermDefinitions[0],
            radarTermDefinitions[1],
            radarTermDefinitions[3],
            TermDefinition(id: "harshness", label: "ハーシュネス", reading: "はーしゅねす", description: "高域の耳障りさの指標です。数値が高いほど刺さりやすい傾向があります。"),
            TermDefinition(id: "crest", label: "Crest", reading: "くれすと", description: "瞬間的なピークと平均音量の差です。小さくなりすぎると平坦に聞こえやすいです。"),
            TermDefinition(id: "lra", label: "LRA", reading: "えるあーるえー", description: "音量変化の幅です。小さくなりすぎるとサビの開放感が弱くなりやすいです。")
        ]
    }

    private var masteringSettingDefinitions: [TermDefinition] {
        [
            bandTermDefinitions[0],
            bandTermDefinitions[1],
            bandTermDefinitions[2],
            bandTermDefinitions[3],
            TermDefinition(id: "deEss", label: "ハーシュネス抑制", reading: "はーしゅねすよくせい", description: "歯擦音や耳に痛い高域だけを抑える処理です。強くしすぎると抜けも弱くなります。"),
            TermDefinition(id: "stereoWidth", label: "ステレオ幅", reading: "すてれおはば", description: "左右への広がり具合です。今の実装では低域は広げず、中高域だけを広げます。")
        ]
    }

    private var compressionBandDefinitions: [TermDefinition] {
        [
            TermDefinition(id: "lowComp", label: "低域コンプ", reading: "ていいきこんぷ", description: "低域のコンプレッサーです。キックやベースの暴れを抑えて、量感を整えます。"),
            TermDefinition(id: "midComp", label: "中域コンプ", reading: "ちゅういきこんぷ", description: "中域のコンプレッサーです。声や主旋律の押し出しを整えます。"),
            TermDefinition(id: "highComp", label: "高域コンプ", reading: "こういきこんぷ", description: "高域のコンプレッサーです。明るさや刺激感の出過ぎを整えます。")
        ]
    }

    private struct ComparisonStageMetrics: Identifiable {
        let id: String
        let label: String
        let color: Color
        let metrics: AudioMetricSnapshot
    }

    private struct DirectionSummaryRow: Identifiable {
        let id: String
        let title: String
        let finalValue: String
        let inputDeltaText: String
        let masteringDeltaText: String
        let inputTint: Color
        let masteringTint: Color
        let tint: Color
        let detail: String
    }

    private struct ComparisonBandRow: Identifiable {
        let id: String
        let label: String
        let rangeDescription: String
        let input: Double
        let corrected: Double?
        let mastered: Double?
    }

    private struct MasteringCurvePoint: Identifiable {
        let id = UUID()
        let order: Int
        let label: String
        let series: String
        let value: Double
    }

    private struct TimelineCurvePoint: Identifiable {
        let id: String
        let time: Double
        let series: String
        let value: Double
    }

    private struct SpectrumCurvePoint: Identifiable {
        let id: String
        let frequencyHz: Double
        let series: String
        let levelDB: Double
    }

    private struct SpectrumDeltaPoint: Identifiable {
        let id: String
        let frequencyHz: Double
        let series: String
        let deltaDB: Double
    }

    private struct MetricTableLayout {
        let labelWidth: CGFloat
        let valueWidth: CGFloat
    }

    private struct MetricTableRow: Identifiable {
        let id = UUID()
        let item: TermDefinition
        let input: Double?
        let corrected: Double?
        let mastered: Double?
        let format: MetricFormat
    }

    private struct TermHelpButton: View {
        let title: String
        let reading: String
        let description: String
        @State private var isPresented = false

        var body: some View {
            Button {
                isPresented.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Text(reading)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(description)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(width: 260, alignment: .leading)
            }
        }
    }

    private struct TermDefinition: Identifiable {
        let id: String
        let label: String
        let reading: String
        let description: String
    }

    private var spectrogramSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("スペクトログラム")
                .font(.headline)

            if let input = job.inputSpectrogram {
                let bounds = combinedSpectrogramBounds(input: input, corrected: job.outputSpectrogram, mastered: job.masteredSpectrogram)
                HStack(alignment: .top, spacing: 14) {
                    spectrogramCard(title: "入力", snapshot: input, tint: .blue, bounds: bounds)
                    spectrogramCard(title: "補正後", snapshot: job.outputSpectrogram ?? .empty, tint: .green, bounds: bounds)
                    spectrogramCard(title: "最終版", snapshot: job.masteredSpectrogram ?? .empty, tint: .orange, bounds: bounds)
                }
            } else {
                Text("音声を選ぶと、ここに入力・補正後・最終版の時間と帯域の変化が表示されます。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func spectrogramCard(title: String, snapshot: SpectrogramSnapshot, tint: Color, bounds: (min: Double, max: Double)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            if snapshot.cells.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(height: 180)
                    .overlay {
                        Text("まだ表示できません")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            } else {
                Chart(snapshot.cells) { cell in
                    RectangleMark(
                        xStart: .value("時間開始", cell.timeStart),
                        xEnd: .value("時間終了", cell.timeEnd),
                        yStart: .value("周波数開始", cell.frequencyStart),
                        yEnd: .value("周波数終了", cell.frequencyEnd)
                    )
                    .foregroundStyle(tint.opacity(spectrogramOpacity(for: cell.levelDB, bounds: bounds)))
                    .lineStyle(.init(lineWidth: 0))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .chartYAxis {
                    AxisMarks(values: [100, 1_000, 10_000]) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let frequency = value.as(Double.self) {
                                Text(frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))")
                            }
                        }
                    }
                }
                .chartXScale(domain: 0 ... max(snapshot.duration, 0.1))
                .chartYScale(domain: 80 ... 24_000, type: .log)
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(Color.black.opacity(0.06))
                        .border(Color.black.opacity(0.08))
                }
                .frame(height: 180)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func combinedSpectrogramBounds(
        input: SpectrogramSnapshot,
        corrected: SpectrogramSnapshot?,
        mastered: SpectrogramSnapshot?
    ) -> (min: Double, max: Double) {
        let snapshots = [input, corrected, mastered].compactMap { $0 }.filter { !$0.cells.isEmpty }
        let minLevel = snapshots.map(\.minLevelDB).min() ?? -96
        let maxLevel = snapshots.map(\.maxLevelDB).max() ?? -24
        return (minLevel, maxLevel)
    }

    private func spectrogramOpacity(for levelDB: Double, bounds: (min: Double, max: Double)) -> Double {
        let normalized = max(0, min(1, (levelDB - bounds.min) / max(bounds.max - bounds.min, 1)))
        return 0.04 + pow(normalized, 0.55) * 0.96
    }

    private func deltaChipColor(for delta: Double?) -> Color {
        guard let delta else { return .secondary }
        let magnitude = abs(delta)
        if magnitude < 0.15 {
            return .secondary
        }
        return delta >= 0 ? .green : .red
    }

    private func deltaChipWidth(for delta: Double?) -> CGFloat {
        guard let delta else { return 18 }
        let magnitude = min(abs(delta), 3)
        return 18 + CGFloat(magnitude / 3) * 34
    }

    private var logSection: some View {
        HStack(alignment: .top, spacing: 14) {
            logCard(title: "補正ログ", text: job.logText, placeholder: "ここに補正ログが表示されます。")
            logCard(title: "マスタリングログ", text: job.masteringLogText, placeholder: "ここにマスタリングログが表示されます。")
        }
    }

    private func logCard(title: String, text: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ScrollView {
                Text(text.isEmpty ? placeholder : text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .top)
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

    private func startCorrectionProcessing() {
        guard let inputFile = job.inputFile else { return }
        let selectionID = inputSelectionID
        let appliedSettings = job.editableCorrectionSettings
        let resolvedAnalysisMode = job.selectedAnalysisMode.resolvedMode
        let initialAnalysis = job.inputCorrectionAnalysisMode == resolvedAnalysisMode ? job.inputCorrectionAnalysis : nil
        job.beginProcessing(appliedSettings: appliedSettings)

        Task {
            do {
                let outputFile = try await AudioProcessingService().process(
                    inputFile: inputFile,
                    denoiseStrength: job.selectedDenoiseStrength,
                    correctionSettings: appliedSettings,
                    analysisMode: job.selectedAnalysisMode,
                    initialAnalysis: initialAnalysis,
                    initialNoiseMeasurements: job.inputNoiseMeasurements
                ) { message in
                    Task { @MainActor in
                        job.appendLog(message)
                    }
                }

                let correctedArtifacts = try await makeAudioAnalysisArtifacts(for: outputFile) { message in
                    Task { @MainActor in
                        job.appendLog(message)
                    }
                }

                await MainActor.run {
                    guard isCurrentInputSelection(selectionID, inputFile: inputFile) else { return }
                    job.finishSuccess(outputFile, appliedSettings: appliedSettings)
                    preview.preparePreview(for: job.inputFile, target: .input, measureLoudness: false)
                    if let inputMetrics = job.inputMetrics {
                        preview.setIntegratedLoudnessLUFS(inputMetrics.integratedLoudnessLUFS, for: .input)
                    }
                    if let previewSnapshot = correctedArtifacts.previewSnapshot {
                        preview.setPreviewSnapshot(
                            previewSnapshot,
                            for: .corrected,
                            sourceURL: outputFile,
                            integratedLoudnessLUFS: correctedArtifacts.metrics.integratedLoudnessLUFS
                        )
                    }
                    preview.preparePreview(for: nil, target: .mastered)
                    job.finishOutputMetricAnalysis(correctedArtifacts.metrics)
                    if let masteringAnalysis = correctedArtifacts.masteringAnalysis {
                        job.finishOutputMasteringAnalysis(masteringAnalysis)
                    }
                    job.finishOutputNoiseMeasurement(correctedArtifacts.noiseMeasurements)
                    job.finishOutputSpectrogram(correctedArtifacts.spectrogram)
                }
            } catch {
                await MainActor.run {
                    guard isCurrentInputSelection(selectionID, inputFile: inputFile) else { return }
                    job.failMetricAnalysis()
                    job.finishFailure(error.localizedDescription)
                }
            }
        }
    }

    private func startMasteringProcessing() {
        guard let correctedFile = job.outputFile else { return }
        let selectionID = inputSelectionID
        let appliedSettings = job.editableMasteringSettings
        job.beginMastering(appliedSettings: appliedSettings)

        Task {
            do {
                let masteredFile = try await MasteringService().process(
                    inputFile: correctedFile,
                    settings: appliedSettings,
                    initialAnalysis: job.outputMasteringAnalysis,
                    referenceNoiseMeasurements: job.outputNoiseMeasurements,
                    originalReferenceFile: job.inputFile,
                    originalReferenceNoiseMeasurements: job.inputNoiseMeasurements
                ) { message in
                    Task { @MainActor in
                        job.appendMasteringLog(message)
                    }
                }

                let masteredArtifacts = try await makeAudioAnalysisArtifacts(for: masteredFile, includeMasteringAnalysis: false) { message in
                    Task { @MainActor in
                        job.appendMasteringLog(message)
                    }
                }

                await MainActor.run {
                    guard isCurrentMasteringSelection(selectionID, correctedFile: correctedFile) else { return }
                    job.finishMasteringSuccess(masteredFile, appliedSettings: appliedSettings)
                    if let previewSnapshot = masteredArtifacts.previewSnapshot {
                        preview.setPreviewSnapshot(
                            previewSnapshot,
                            for: .mastered,
                            sourceURL: masteredFile,
                            integratedLoudnessLUFS: masteredArtifacts.metrics.integratedLoudnessLUFS
                        )
                    }
                    job.finishMasteredMetricAnalysis(masteredArtifacts.metrics)
                    job.finishMasteredNoiseMeasurement(masteredArtifacts.noiseMeasurements)
                    job.finishMasteredSpectrogram(masteredArtifacts.spectrogram)
                }
            } catch {
                await MainActor.run {
                    guard isCurrentMasteringSelection(selectionID, correctedFile: correctedFile) else { return }
                    job.failMetricAnalysis()
                    job.finishMasteringFailure(error.localizedDescription)
                }
            }
        }
    }

    private enum MetricTarget {
        case input
        case corrected
        case mastered
    }

    private enum MetricFormat {
        case dBFS
        case dB
        case lu
        case lufs
        case hertz
        case ratio(Int)
        case score(Int)
    }

    private struct AudioAnalysisArtifacts: Sendable {
        let previewSnapshot: AudioPreviewSnapshot?
        let metrics: AudioMetricSnapshot
        let masteringAnalysis: MasteringAnalysis?
        let correctionAnalysis: AnalysisData?
        let correctionAnalysisMode: AudioAnalysisMode?
        let noiseMeasurements: NoiseMeasurementSnapshot
        let spectrogram: SpectrogramSnapshot
    }

    private func analyzeMetrics(for url: URL, target: MetricTarget, selectionID: UUID) {
        guard !hasCachedAnalysis(for: target, fileURL: url) else { return }
        job.beginMetricAnalysis()

        Task {
            do {
                let artifacts = try await makeAnalysisArtifacts(
                    for: url,
                    includePreview: false,
                    includeMasteringAnalysis: target == .corrected,
                    correctionAnalysisMode: target == .input ? job.selectedAnalysisMode.resolvedMode : nil,
                    logHandler: displayAnalysisLogHandler(for: target)
                )

                await MainActor.run {
                    guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url) else { return }
                    switch target {
                    case .input:
                        job.finishInputMetricAnalysis(artifacts.metrics)
                        preview.setIntegratedLoudnessLUFS(artifacts.metrics.integratedLoudnessLUFS, for: .input)
                        if let analysis = artifacts.correctionAnalysis, let mode = artifacts.correctionAnalysisMode {
                            job.finishInputCorrectionAnalysis(analysis, mode: mode)
                        }
                        job.finishInputNoiseMeasurement(artifacts.noiseMeasurements)
                        job.finishInputSpectrogram(artifacts.spectrogram)
                    case .corrected:
                        job.finishOutputMetricAnalysis(artifacts.metrics)
                        preview.setIntegratedLoudnessLUFS(artifacts.metrics.integratedLoudnessLUFS, for: .corrected)
                        if let masteringAnalysis = artifacts.masteringAnalysis {
                            job.finishOutputMasteringAnalysis(masteringAnalysis)
                        }
                        job.finishOutputNoiseMeasurement(artifacts.noiseMeasurements)
                        job.finishOutputSpectrogram(artifacts.spectrogram)
                    case .mastered:
                        job.finishMasteredMetricAnalysis(artifacts.metrics)
                        preview.setIntegratedLoudnessLUFS(artifacts.metrics.integratedLoudnessLUFS, for: .mastered)
                        job.finishMasteredNoiseMeasurement(artifacts.noiseMeasurements)
                        job.finishMasteredSpectrogram(artifacts.spectrogram)
                    }
                }
            } catch {
                await MainActor.run {
                    guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url) else { return }
                    job.failMetricAnalysis()
                }
            }
        }
    }

    private func makeAudioAnalysisArtifacts(
        for url: URL,
        includeMasteringAnalysis: Bool = true,
        logHandler: (@Sendable (String) -> Void)? = nil
    ) async throws -> AudioAnalysisArtifacts {
        try await makeAnalysisArtifacts(
            for: url,
            includePreview: true,
            includeMasteringAnalysis: includeMasteringAnalysis,
            correctionAnalysisMode: nil,
            logHandler: logHandler
        )
    }

    private func makeAnalysisArtifacts(
        for url: URL,
        includePreview: Bool,
        includeMasteringAnalysis: Bool,
        correctionAnalysisMode: AudioAnalysisMode?,
        logHandler: (@Sendable (String) -> Void)? = nil
    ) async throws -> AudioAnalysisArtifacts {
        try await Task.detached(priority: .utility) {
            let signal = try await Self.measureDisplayAnalysis("ファイル読み込み", logHandler: logHandler) {
                try AudioFileService.loadAudio(from: url)
            }
            async let previewSnapshot: AudioPreviewSnapshot? = Self.measureOptionalDisplayAnalysis("プレビュー生成", isEnabled: includePreview, logHandler: logHandler) {
                AudioFileService.makePreviewSnapshot(from: signal)
            }
            async let metrics = Self.measureDisplayAnalysis("比較指標", logHandler: logHandler) {
                try await AudioComparisonService.analyzeConcurrently(signal: signal)
            }
            async let masteringAnalysis: MasteringAnalysis? = Self.measureOptionalDisplayAnalysis("マスタリング解析", isEnabled: includeMasteringAnalysis, logHandler: logHandler) {
                MasteringAnalysisService.analyze(signal: signal)
            }
            async let correctionAnalysis: AnalysisData? = Self.measureCorrectionAnalysis(correctionAnalysisMode, signal: signal, logHandler: logHandler)
            async let noiseMeasurements = Self.measureDisplayAnalysis("ノイズ測定", logHandler: logHandler) {
                NoiseMeasurementService.analyze(signal: signal)
            }
            async let spectrogram = Self.measureDisplayAnalysis("スペクトログラム生成", logHandler: logHandler) {
                AudioFileService.makeSpectrogramSnapshot(from: signal)
            }
            return try await AudioAnalysisArtifacts(
                previewSnapshot: previewSnapshot,
                metrics: metrics,
                masteringAnalysis: masteringAnalysis,
                correctionAnalysis: correctionAnalysis,
                correctionAnalysisMode: correctionAnalysisMode,
                noiseMeasurements: noiseMeasurements,
                spectrogram: spectrogram
            )
        }.value
    }

    private func displayAnalysisLogHandler(for target: MetricTarget) -> (@Sendable (String) -> Void) {
        switch target {
        case .input, .corrected:
            { message in
                Task { @MainActor in
                    job.appendLog(message)
                }
            }
        case .mastered:
            { message in
                Task { @MainActor in
                    job.appendMasteringLog(message)
                }
            }
        }
    }

    static func measureDisplayAnalysis<T: Sendable>(
        _ label: String,
        logHandler: (@Sendable (String) -> Void)?,
        work: @Sendable () async throws -> T
    ) async throws -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let result = try await work()
            logHandler?("表示解析/計測: \(label): \(formatProcessingDuration(displayAnalysisDurationSeconds(since: start)))")
            return result
        } catch {
            logHandler?("表示解析/計測: \(label): \(formatProcessingDuration(displayAnalysisDurationSeconds(since: start)))")
            throw error
        }
    }

    static func measureOptionalDisplayAnalysis<T: Sendable>(
        _ label: String,
        isEnabled: Bool,
        logHandler: (@Sendable (String) -> Void)?,
        work: @Sendable () async throws -> T
    ) async throws -> T? {
        guard isEnabled else { return nil }
        return try await measureDisplayAnalysis(label, logHandler: logHandler, work: work)
    }

    private static func measureCorrectionAnalysis(
        _ mode: AudioAnalysisMode?,
        signal: AudioSignal,
        logHandler: (@Sendable (String) -> Void)?
    ) async throws -> AnalysisData? {
        guard let mode else { return nil }
        return try await measureDisplayAnalysis("補正解析", logHandler: logHandler) {
            AudioAnalyzer(mode: mode).analyze(signal: signal)
        }
    }

    private static func displayAnalysisDurationSeconds(since start: UInt64) -> Double {
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000_000
    }

    private func preparePreviewCards() {
        preview.preparePreview(for: job.inputFile, target: .input, measureLoudness: false)
        if let inputMetrics = job.inputMetrics {
            preview.setIntegratedLoudnessLUFS(inputMetrics.integratedLoudnessLUFS, for: .input)
        }

        preview.preparePreview(for: job.hasExistingOutput ? job.outputFile : nil, target: .corrected, measureLoudness: job.outputMetrics == nil)
        if let outputMetrics = job.outputMetrics {
            preview.setIntegratedLoudnessLUFS(outputMetrics.integratedLoudnessLUFS, for: .corrected)
        }

        preview.preparePreview(for: job.hasExistingMasteredOutput ? job.masteredOutputFile : nil, target: .mastered, measureLoudness: job.masteredMetrics == nil)
        if let masteredMetrics = job.masteredMetrics {
            preview.setIntegratedLoudnessLUFS(masteredMetrics.integratedLoudnessLUFS, for: .mastered)
        }
    }

    private func hasCachedAnalysis(for target: MetricTarget, fileURL: URL) -> Bool {
        switch target {
        case .input:
            return job.inputFile == fileURL
                && job.inputMetrics != nil
                && job.inputNoiseMeasurements != nil
                && job.inputSpectrogram != nil
                && job.inputCorrectionAnalysis != nil
                && job.inputCorrectionAnalysisMode == job.selectedAnalysisMode.resolvedMode
        case .corrected:
            return job.outputFile == fileURL
                && job.outputMetrics != nil
                && job.outputMasteringAnalysis != nil
                && job.outputNoiseMeasurements != nil
                && job.outputSpectrogram != nil
        case .mastered:
            return job.masteredOutputFile == fileURL
                && job.masteredMetrics != nil
                && job.masteredNoiseMeasurements != nil
                && job.masteredSpectrogram != nil
        }
    }

    @discardableResult
    private func beginInputSelection(for url: URL) -> UUID {
        let selectionID = UUID()
        inputSelectionID = selectionID
        PreviewFileStore.removeAllPreviewFiles()
        job.prepareForSelection(url)
        preview.stopPlayback()
        preparePreviewCards()
        return selectionID
    }

    private func exportCorrectedAudio() {
        guard let sourceURL = job.outputFile, let inputFile = job.inputFile else { return }
        let suggestedName = AudioProcessingService.defaultOutputURL(for: inputFile).lastPathComponent
        let allowedTypes = allowedAudioTypes(for: sourceURL.pathExtension)
        guard let destinationURL = FilePanelService.chooseSaveLocation(suggestedFileName: suggestedName, allowedContentTypes: allowedTypes) else {
            return
        }
        do {
            try replaceFile(from: sourceURL, to: destinationURL)
            job.finishCorrectedExport(destinationURL)
        } catch {
            job.finishFailure(error.localizedDescription)
        }
    }

    private func exportMasteredAudio() {
        guard let sourceURL = job.masteredOutputFile else { return }
        let baseURL = job.inputFile.map { MasteringService.defaultOutputURL(for: $0) } ?? sourceURL
        let suggestedName = baseURL.lastPathComponent
        let allowedTypes = allowedAudioTypes(for: sourceURL.pathExtension)
        guard let destinationURL = FilePanelService.chooseSaveLocation(suggestedFileName: suggestedName, allowedContentTypes: allowedTypes) else {
            return
        }
        do {
            try replaceFile(from: sourceURL, to: destinationURL)
            job.finishMasteredExport(destinationURL)
        } catch {
            job.finishMasteringFailure(error.localizedDescription)
        }
    }

    private func replaceFile(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func allowedAudioTypes(for fileExtension: String) -> [UTType] {
        [UTType(filenameExtension: fileExtension), AudioFileService.outputContentType, .audio].compactMap { $0 }
    }

    private func isCurrentInputSelection(_ selectionID: UUID, inputFile: URL) -> Bool {
        inputSelectionID == selectionID && job.inputFile == inputFile
    }

    private func isCurrentMasteringSelection(_ selectionID: UUID, correctedFile: URL) -> Bool {
        inputSelectionID == selectionID && job.outputFile == correctedFile
    }

    private func isCurrentMetricSelection(target: MetricTarget, selectionID: UUID, fileURL: URL) -> Bool {
        guard inputSelectionID == selectionID else { return false }

        switch target {
        case .input:
            return job.inputFile == fileURL
        case .corrected:
            return job.outputFile == fileURL
        case .mastered:
            return job.masteredOutputFile == fileURL
        }
    }

    private func formattedValue(_ value: Double, format: MetricFormat) -> String {
        switch format {
        case .dBFS:
            return String(format: "%.2f dB", value)
        case .dB:
            return String(format: "%.2f dB", value)
        case .lu:
            return String(format: "%.2f LU", value)
        case .lufs:
            return String(format: "%.1f LUFS", value)
        case .hertz:
            return String(format: "%.0f Hz", value)
        case .ratio(let decimals):
            return String(format: "%.\(decimals)f", value)
        case .score(let decimals):
            return String(format: "%.\(decimals)f", value)
        }
    }

    private func formattedDelta(_ value: Double, format: MetricFormat) -> String {
        switch format {
        case .dBFS:
            return String(format: value >= 0 ? "+%.2f dB" : "%.2f dB", value)
        case .dB:
            return String(format: value >= 0 ? "+%.2f dB" : "%.2f dB", value)
        case .lu:
            return String(format: value >= 0 ? "+%.2f LU" : "%.2f LU", value)
        case .lufs:
            return String(format: value >= 0 ? "+%.1f LU" : "%.1f LU", value)
        case .hertz:
            return String(format: value >= 0 ? "+%.0f Hz" : "%.0f Hz", value)
        case .ratio(let decimals):
            return String(format: value >= 0 ? "+%.\(decimals)f" : "%.\(decimals)f", value)
        case .score(let decimals):
            return String(format: value >= 0 ? "+%.\(decimals)f" : "%.\(decimals)f", value)
        }
    }

    private func summaryDirectionColor(delta: Double) -> Color {
        if abs(delta) < 0.0001 {
            return .secondary
        }
        return delta >= 0 ? .green : .red
    }

    private func summaryImprovementColor(beforeDistance: Double, afterDistance: Double) -> Color {
        if abs(afterDistance - beforeDistance) < 0.0001 {
            return .secondary
        }
        return afterDistance < beforeDistance ? .green : .orange
    }
}

#Preview {
    ContentView()
}
