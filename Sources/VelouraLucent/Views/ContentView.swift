import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var job = ProcessingJob()
    @State private var preview = AudioPreviewController()
    @State private var inputSelectionID = UUID()

    private let metricColumns = [
        GridItem(.flexible(minimum: 180), spacing: 12),
        GridItem(.flexible(minimum: 180), spacing: 12),
        GridItem(.flexible(minimum: 180), spacing: 12)
    ]

    private let comparisonCardColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                inputSection
                correctionSection
                outputSection
                masteringSection
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

    private var correctionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("補正")
                .font(.headline)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ノイズ除去の強さ")
                        .font(.subheadline.weight(.semibold))
                    Picker("ノイズ除去の強さ", selection: $job.selectedDenoiseStrength) {
                        ForEach(DenoiseStrength.allCases) { strength in
                            Text(strength.title).tag(strength)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(job.isProcessing)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("説明")
                        .font(.subheadline.weight(.semibold))
                    Text(job.selectedDenoiseStrength.summary)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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

    private var masteringSection: some View {
        MasteringSettingsPanel(job: job)
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
                completedSteps: job.completedSteps
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
        completedSteps: Set<ProcessingStep>
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
                        isActive: activeStep == step
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
                        isActive: job.masteringActiveStep == step
                    )
                }
            }
        }
    }

    private func progressBadge(title: String, isCompleted: Bool, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : isActive ? "dot.circle.fill" : "circle")
                .foregroundStyle(isCompleted ? Color.green : isActive ? Color.orange : Color.secondary)
            Text(title)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isActive ? Color.orange.opacity(0.14) : isCompleted ? Color.green.opacity(0.14) : Color.secondary.opacity(0.08))
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
            } else {
                Text("音声を選ぶと、ここに入力・補正後・最終版の比較がまとめて表示されます。")
                    .foregroundStyle(.secondary)
            }
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
                    comparisonRadarCard(stages: stages)
                    comparisonBalanceCurveCard(stages: stages)
                }

                LazyVGrid(columns: comparisonCardColumns, alignment: .leading, spacing: 14) {
                    shortTermLoudnessCard(stages: stages)
                    spectrumComparisonCard(input: job.inputMetrics, corrected: corrected, mastered: mastered)
                    dynamicsTrendCard(stages: stages)
                    correlationMeterCard(input: job.inputMetrics, corrected: corrected, mastered: mastered)
                }

                Text("左で仕上がりの方向、右で帯域の触り方を見比べられます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("最終版の比較は、マスタリングを実行すると表示されます。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func comparisonRadarCard(stages: [ComparisonStageMetrics]) -> some View {
        let axes = comparisonRadarAxes(stages: stages)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("仕上がりの方向")
                    .font(.headline)
                Spacer()
                termHelpButton(
                    title: "レーダーチャートの見方",
                    reading: "れーだーちゃーとのみかた",
                    description: "外側ほど、その指標が強い状態です。緑が補正後、オレンジが最終版を表します。"
                )
            }

            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                let center = CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
                let radius = size * 0.37
                let ringColor = Color.secondary.opacity(0.22)

                ZStack {
                    ForEach(1...4, id: \.self) { step in
                        radarPolygonPath(
                            values: Array(repeating: Double(step) / 4.0, count: axes.count),
                            center: center,
                            radius: radius
                        )
                        .stroke(ringColor, lineWidth: 1.4)
                    }

                    ForEach(Array(axes.enumerated()), id: \.offset) { index, axis in
                        Path { path in
                            path.move(to: center)
                            path.addLine(to: radarPoint(value: 1, index: index, total: axes.count, center: center, radius: radius))
                        }
                        .stroke(ringColor, lineWidth: 1.4)

                        Text(axis.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .position(
                                radarPoint(value: 1.24, index: index, total: axes.count, center: center, radius: radius)
                            )
                    }

                    ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                        let values = axes.map { $0.values[index] }
                        radarPolygonPath(
                            values: values,
                            center: center,
                            radius: radius
                        )
                        .fill(stage.color.opacity(0.18))

                        radarPolygonPath(
                            values: values,
                            center: center,
                            radius: radius
                        )
                        .stroke(stage.color, style: StrokeStyle(lineWidth: 3.2, dash: stage.id == "input" ? [7, 4] : []))
                    }
                }
            }
            .frame(height: 360)

            chartLegend(stages: stages)
            termHelpGrid(items: radarTermDefinitions)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 500, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
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
                    description: "場面ごとの音量感です。線が近づきすぎると、抑揚が少なくなっている可能性があります。"
                )
            }

            timelineLineChart(points: points, yTitle: "LUFS", yDomain: minValue ... maxValue)
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
                    description: "入力、補正後、最終版の周波数ごとの量を重ね、下段で補正と仕上げの差分を見ます。"
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
                            Text(String(format: "%.0f dB", number))
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

    private func comparisonRadarAxes(stages: [ComparisonStageMetrics]) -> [RadarAxisDatum] {
        let targetLoudness = Double(job.editableMasteringSettings.targetLoudness)
        let targetPeak = Double(job.editableMasteringSettings.peakCeilingDB)

        return [
            RadarAxisDatum(
                label: "ラウドネス",
                values: stages.map { loudnessRadarScore($0.metrics.integratedLoudnessLUFS, target: targetLoudness) }
            ),
            RadarAxisDatum(
                label: "トゥルーピーク",
                values: stages.map { safetyRadarScore($0.metrics.truePeakDBFS, target: targetPeak) }
            ),
            RadarAxisDatum(
                label: "明瞭度",
                values: stages.map { listenabilityRadarScore($0.metrics) }
            ),
            RadarAxisDatum(
                label: "ステレオ幅",
                values: stages.map { widthRadarScore($0.metrics.stereoWidth) }
            ),
            RadarAxisDatum(
                label: "高域バランス",
                values: stages.map { brightnessRadarScore($0.metrics) }
            )
        ]
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
                xStart: .value("注目帯域開始", 6_000),
                xEnd: .value("注目帯域終了", 10_000),
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
                        Text(String(format: "%.0f dB", number))
                    }
                }
            }
        }
    }

    private func spectrumDeltaChart(points: [SpectrumDeltaPoint], yDomain: ClosedRange<Double>) -> some View {
        Chart {
            RectangleMark(
                xStart: .value("注目帯域開始", 6_000),
                xEnd: .value("注目帯域終了", 10_000),
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
                Text("帯域別の見え方")
                    .font(.title3.weight(.bold))
                Spacer()
                termHelpButton(
                    title: "帯域別の見え方",
                    reading: "たいいきべつのみえかた",
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
                Text(value.map { formattedValue($0, format: .dBFS) } ?? "--")
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
            Text(value.map { formattedDelta($0, format: .dBFS) } ?? "--")
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
            MetricTableRow(item: bandTermDefinitions[0], input: inputBandValue(input, id: "low"), corrected: corrected.flatMap { inputBandValue($0, id: "low") }, mastered: mastered.flatMap { inputBandValue($0, id: "low") }, format: .dBFS),
            MetricTableRow(item: bandTermDefinitions[1], input: inputBandValue(input, id: "lowMid"), corrected: corrected.flatMap { inputBandValue($0, id: "lowMid") }, mastered: mastered.flatMap { inputBandValue($0, id: "lowMid") }, format: .dBFS),
            MetricTableRow(item: bandTermDefinitions[2], input: inputBandValue(input, id: "presence"), corrected: corrected.flatMap { inputBandValue($0, id: "presence") }, mastered: mastered.flatMap { inputBandValue($0, id: "presence") }, format: .dBFS),
            MetricTableRow(item: bandTermDefinitions[3], input: inputBandValue(input, id: "air"), corrected: corrected.flatMap { inputBandValue($0, id: "air") }, mastered: mastered.flatMap { inputBandValue($0, id: "air") }, format: .dBFS)
        ]
    }

    private func metricTableLayout(for width: CGFloat) -> MetricTableLayout {
        let labelWidth = max(165, width * 0.30)
        let valueWidth = max(110, (width - labelWidth) / 3)
        return MetricTableLayout(labelWidth: labelWidth, valueWidth: valueWidth)
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
            TermDefinition(id: "loudness", label: "ラウドネス", reading: "らうどねす", description: "曲全体の平均的な音量感です。配信先で聞こえる大きさの目安になります。"),
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
            TermDefinition(id: "low", label: "低域", reading: "ていいき", description: "0Hz〜5kHz の比較用まとめ帯域です。低音から中域の主要成分をざっくり含みます。"),
            TermDefinition(id: "presence", label: "中高域", reading: "ちゅうこういき", description: "5kHz〜10kHz の帯域です。子音の明瞭さや抜けに関わりやすい帯域です。"),
            TermDefinition(id: "high", label: "高域", reading: "こういき", description: "10kHz〜16kHz の帯域です。明るさやきらめきに関わります。"),
            TermDefinition(id: "air", label: "超高域", reading: "ちょうこういき", description: "16kHz〜24kHz の帯域です。空気感や高域の余韻に関わります。")
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

    private func loudnessRadarScore(_ value: Double, target: Double) -> Double {
        max(0.12, 1 - abs(value - target) / 6.0)
    }

    private func safetyRadarScore(_ truePeak: Double, target: Double) -> Double {
        if truePeak <= target {
            return min(1, 0.78 + (target - truePeak) * 0.12)
        }
        return max(0.10, 0.78 - (truePeak - target) * 0.6)
    }

    private func listenabilityRadarScore(_ metrics: AudioMetricSnapshot) -> Double {
        let lowMid = metrics.masteringBandEnergies.first { $0.id == "lowMid" }?.levelDB ?? -24
        let lowMidScore = max(0, min(1, 1 - (lowMid + 18) / 18))
        let harshnessScore = max(0, min(1, 1 - metrics.harshnessScore))
        return max(0.08, min(1, harshnessScore * 0.75 + lowMidScore * 0.25))
    }

    private func widthRadarScore(_ value: Double) -> Double {
        max(0.10, min(1, value / 1.20))
    }

    private func brightnessRadarScore(_ metrics: AudioMetricSnapshot) -> Double {
        let presence = metrics.masteringBandEnergies.first { $0.id == "presence" }?.levelDB ?? -24
        let air = metrics.masteringBandEnergies.first { $0.id == "air" }?.levelDB ?? -24
        let average = (presence + air) * 0.5
        return max(0.08, min(1, (average + 42) / 30))
    }

    private func radarPolygonPath(values: [Double], center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }

        for index in values.indices {
            let point = radarPoint(value: values[index], index: index, total: values.count, center: center, radius: radius)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    private func radarPoint(value: Double, index: Int, total: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = Angle.degrees(-90 + (360.0 / Double(total)) * Double(index)).radians
        let scaledRadius = radius * CGFloat(max(0, min(1, value)))
        return CGPoint(
            x: center.x + cos(angle) * scaledRadius,
            y: center.y + sin(angle) * scaledRadius
        )
    }

    private struct RadarAxisDatum {
        let label: String
        let values: [Double]
    }

    private struct ComparisonStageMetrics: Identifiable {
        let id: String
        let label: String
        let color: Color
        let metrics: AudioMetricSnapshot
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

    private func comparisonSection(
        title: String,
        inputMetrics: AudioMetricSnapshot?,
        outputMetrics: AudioMetricSnapshot?,
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if let inputMetrics {
                VStack(spacing: 12) {
                    LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 12) {
                        metricCard(title: "Peak", input: inputMetrics.peakDBFS, output: outputMetrics?.peakDBFS, format: .dBFS, positiveIsBetter: false)
                        metricCard(title: "RMS", input: inputMetrics.rmsDBFS, output: outputMetrics?.rmsDBFS, format: .dBFS, positiveIsBetter: false)
                        metricCard(title: "重心", input: inputMetrics.centroidHz, output: outputMetrics?.centroidHz, format: .hertz, positiveIsBetter: true)
                        metricCard(title: "12kHz+", input: inputMetrics.hf12Ratio, output: outputMetrics?.hf12Ratio, format: .ratio(5), positiveIsBetter: true)
                        metricCard(title: "16kHz+", input: inputMetrics.hf16Ratio, output: outputMetrics?.hf16Ratio, format: .ratio(6), positiveIsBetter: true)
                        metricCard(title: "18kHz+", input: inputMetrics.hf18Ratio, output: outputMetrics?.hf18Ratio, format: .ratio(6), positiveIsBetter: true)
                    }

                    bandChart(input: inputMetrics.bandEnergies, output: outputMetrics?.bandEnergies ?? [])
                }
            } else {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metricCard(title: String, input: Double, output: Double?, format: MetricFormat, positiveIsBetter: Bool) -> some View {
        let delta = output.map { $0 - input }
        let color: Color = {
            guard let delta else { return .secondary }
            if abs(delta) < 0.000001 { return .secondary }
            let improved = positiveIsBetter ? delta > 0 : delta < 0
            return improved ? .green : .orange
        }()

        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text("入力  \(formattedValue(input, format: format))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("出力  \(output.map { formattedValue($0, format: format) } ?? "--")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(output == nil ? .secondary : .primary)
            Text(delta.map { "差分  \(formattedDelta($0, format: format))" } ?? "差分  --")
                .font(.caption.monospacedDigit())
                .foregroundStyle(color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func bandChart(input: [BandEnergyMetric], output: [BandEnergyMetric]) -> some View {
        let outputMap = Dictionary(uniqueKeysWithValues: output.map { ($0.id, $0) })
        let pairs = input.map { ($0, outputMap[$0.id]) }
        let levels = pairs.flatMap { [$0.0.levelDB, $0.1?.levelDB ?? $0.0.levelDB] }
        let maxLevel = (levels.max() ?? 0) + 3
        let minLevel = min((levels.min() ?? -60), -40) - 3

        return VStack(alignment: .leading, spacing: 10) {
            Text("帯域別の見え方")
                .font(.headline)

            ForEach(pairs, id: \.0.id) { inputMetric, outputMetric in
                let delta = outputMetric.map { $0.levelDB - inputMetric.levelDB }
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(inputMetric.label)
                            .font(.caption.bold())
                        Text(inputMetric.rangeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        bandBar(title: "入力", value: inputMetric.levelDB, minLevel: minLevel, maxLevel: maxLevel, tint: .blue)
                        bandBar(title: "出力", value: outputMetric?.levelDB, minLevel: minLevel, maxLevel: maxLevel, tint: .green)
                    }

                    Spacer(minLength: 0)

                    diffSummary(delta: delta)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func diffSummary(delta: Double?) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text("差分")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(delta.map { formattedDelta($0, format: .dBFS) } ?? "--")
                .font(.caption.monospacedDigit())
                .foregroundStyle(deltaChipColor(for: delta))

            Capsule()
                .fill(deltaChipColor(for: delta).opacity(delta == nil ? 0.18 : 0.9))
                .frame(width: deltaChipWidth(for: delta), height: 8)
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.35), lineWidth: delta == nil ? 0 : 0.6)
                }
        }
        .frame(width: 94, alignment: .trailing)
    }

    private func bandBar(title: String, value: Double?, minLevel: Double, maxLevel: Double, tint: Color) -> some View {
        let normalized = value.map { max(0, min(1, ($0 - minLevel) / max(maxLevel - minLevel, 1))) } ?? 0

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value.map { formattedValue($0, format: .dBFS) } ?? "--")
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
        .frame(maxWidth: .infinity)
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
        let activeBoost = job.masteringActiveStep == nil ? 0 : 0.5
        return min(0.98, (completed + activeBoost) / total)
    }

    private var masteringProgressLabel: String {
        if let step = job.masteringActiveStep {
            return "\(step.title) を実行中"
        }
        return job.masteringStatusMessage
    }

    private func startCorrectionProcessing() {
        guard let inputFile = job.inputFile else { return }
        let selectionID = inputSelectionID
        job.beginProcessing()

        Task {
            do {
                let outputFile = try await AudioProcessingService().process(
                    inputFile: inputFile,
                    denoiseStrength: job.selectedDenoiseStrength
                ) { message in
                    Task { @MainActor in
                        job.appendLog(message)
                    }
                }

                let correctedArtifacts = try await makeAudioAnalysisArtifacts(for: outputFile)

                await MainActor.run {
                    guard isCurrentInputSelection(selectionID, inputFile: inputFile) else { return }
                    job.finishSuccess(outputFile)
                    preview.preparePreview(for: job.inputFile, target: .input)
                    preview.setPreviewSnapshot(correctedArtifacts.previewSnapshot, for: .corrected, sourceURL: outputFile)
                    preview.preparePreview(for: nil, target: .mastered)
                    job.finishOutputMetricAnalysis(correctedArtifacts.metrics)
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
        job.beginMastering()

        Task {
            do {
                let masteredFile = try await MasteringService().process(
                    inputFile: correctedFile,
                    settings: job.editableMasteringSettings
                ) { message in
                    Task { @MainActor in
                        job.appendMasteringLog(message)
                    }
                }

                let masteredArtifacts = try await makeAudioAnalysisArtifacts(for: masteredFile)

                await MainActor.run {
                    guard isCurrentMasteringSelection(selectionID, correctedFile: correctedFile) else { return }
                    job.finishMasteringSuccess(masteredFile)
                    preview.setPreviewSnapshot(masteredArtifacts.previewSnapshot, for: .mastered, sourceURL: masteredFile)
                    job.finishMasteredMetricAnalysis(masteredArtifacts.metrics)
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
        let previewSnapshot: AudioPreviewSnapshot
        let metrics: AudioMetricSnapshot
        let spectrogram: SpectrogramSnapshot
    }

    private struct MetricAnalysisArtifacts: Sendable {
        let metrics: AudioMetricSnapshot
        let spectrogram: SpectrogramSnapshot
    }

    private func analyzeMetrics(for url: URL, target: MetricTarget, selectionID: UUID) {
        job.beginMetricAnalysis()

        Task {
            do {
                let artifacts = try await makeMetricAnalysisArtifacts(for: url)

                await MainActor.run {
                    guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url) else { return }
                    switch target {
                    case .input:
                        job.finishInputMetricAnalysis(artifacts.metrics)
                        job.finishInputSpectrogram(artifacts.spectrogram)
                    case .corrected:
                        job.finishOutputMetricAnalysis(artifacts.metrics)
                        job.finishOutputSpectrogram(artifacts.spectrogram)
                    case .mastered:
                        job.finishMasteredMetricAnalysis(artifacts.metrics)
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

    private func makeAudioAnalysisArtifacts(for url: URL) async throws -> AudioAnalysisArtifacts {
        try await Task.detached(priority: .utility) {
            let signal = try AudioFileService.loadAudio(from: url)
            async let previewSnapshot = AudioFileService.makePreviewSnapshot(from: signal)
            async let metrics = try await AudioComparisonService.analyzeConcurrently(signal: signal)
            async let spectrogram = AudioFileService.makeSpectrogramSnapshot(from: signal)
            return try await AudioAnalysisArtifacts(
                previewSnapshot: previewSnapshot,
                metrics: metrics,
                spectrogram: spectrogram
            )
        }.value
    }

    private func makeMetricAnalysisArtifacts(for url: URL) async throws -> MetricAnalysisArtifacts {
        try await Task.detached(priority: .utility) {
            let signal = try AudioFileService.loadAudio(from: url)
            async let metrics = try await AudioComparisonService.analyzeConcurrently(signal: signal)
            async let spectrogram = AudioFileService.makeSpectrogramSnapshot(from: signal)
            return try await MetricAnalysisArtifacts(metrics: metrics, spectrogram: spectrogram)
        }.value
    }

    private func preparePreviewCards() {
        preview.preparePreview(for: job.inputFile, target: .input)
        preview.preparePreview(for: job.hasExistingOutput ? job.outputFile : nil, target: .corrected)
        preview.preparePreview(for: job.hasExistingMasteredOutput ? job.masteredOutputFile : nil, target: .mastered)
    }

    @discardableResult
    private func beginInputSelection(for url: URL) -> UUID {
        let selectionID = UUID()
        inputSelectionID = selectionID
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
            return String(format: value >= 0 ? "+%.1f LUFS" : "%.1f LUFS", value)
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
