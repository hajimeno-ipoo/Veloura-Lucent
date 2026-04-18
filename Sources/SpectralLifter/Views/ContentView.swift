import AppKit
import SwiftUI

struct ContentView: View {
    @State private var job = ProcessingJob()
    @State private var preview = AudioPreviewController()

    private let metricColumns = [
        GridItem(.flexible(minimum: 180), spacing: 12),
        GridItem(.flexible(minimum: 180), spacing: 12),
        GridItem(.flexible(minimum: 180), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                inputSection
                outputSection
                masteringSection
                previewSection
                correctionActionSection
                masteringActionSection
                progressSection
                metricsSection
                logSection
            }
            .padding(24)
        }
        .frame(minWidth: 1_060, minHeight: 860)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Spectral Lifter")
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
                        job.prepareForSelection(url)
                        preview.stopPlayback()
                        preparePreviewCards()
                        analyzeMetrics(for: url, target: .input)
                    }
                }
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("書き出し先")
                .font(.headline)

            outputPathRow(title: "補正後", fileURL: job.outputFile, placeholder: "入力ファイルを選ぶと自動で決まります")
            outputPathRow(title: "最終版", fileURL: job.masteredOutputFile, placeholder: "補正後ファイルを元に自動で決まります")
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
        VStack(alignment: .leading, spacing: 10) {
            Text("マスタリング")
                .font(.headline)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("仕上がり")
                        .font(.subheadline.weight(.semibold))
                    Picker("仕上がり", selection: $job.selectedMasteringProfile) {
                        ForEach(MasteringProfile.allCases) { profile in
                            Text(profile.title).tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("説明")
                        .font(.subheadline.weight(.semibold))
                    Text(job.selectedMasteringProfile.summary)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("試聴比較")
                .font(.headline)

            HStack(spacing: 14) {
                previewCard(title: "入力音声", target: .input, fileURL: job.inputFile, tint: .blue)
                previewCard(title: "補正後", target: .corrected, fileURL: job.hasExistingOutput ? job.outputFile : nil, tint: .green)
                previewCard(title: "最終版", target: .mastered, fileURL: job.hasExistingMasteredOutput ? job.masteredOutputFile : nil, tint: .orange)
            }
        }
    }

    private func previewCard(title: String, target: AudioPreviewTarget, fileURL: URL?, tint: Color) -> some View {
        let snapshot = preview.snapshot(for: target)
        let liveBands = preview.liveBandLevels[target] ?? AudioBandCatalog.previewBands.map {
            LiveBandSample(id: $0.id, label: $0.label, level: 0)
        }
        let isActive = preview.activeTarget == target
        let playbackState = preview.playbackState(for: target)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(preview.playbackTimeText(for: target))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(fileURL?.lastPathComponent ?? "まだ確認できません")
                .lineLimit(2)
                .foregroundStyle(fileURL == nil ? .secondary : .primary)

            waveformPreview(snapshot: snapshot, tint: tint, progress: preview.playbackProgress(for: target))

            VStack(spacing: 6) {
                ForEach(liveBands) { band in
                    HStack(spacing: 8) {
                        Text(band.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .leading)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.12))
                                Capsule()
                                    .fill(tint.opacity(isActive ? 0.95 : 0.45))
                                    .frame(width: proxy.size.width * band.level)
                            }
                        }
                        .frame(height: 6)
                    }
                    .frame(height: 10)
                }
            }

            HStack(spacing: 8) {
                Button(primaryPlaybackButtonTitle(for: target)) {
                    preview.startPlayback(for: fileURL, target: target)
                }
                .disabled(fileURL == nil || playbackState == .playing)

                Button("一時停止") {
                    preview.pausePlayback(target: target)
                }
                .disabled(playbackState != .playing)

                Button("停止") {
                    preview.stopPlayback(target: target)
                }
                .disabled(fileURL == nil || playbackState == .stopped)

                if let fileURL {
                    Button("Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(tint.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func primaryPlaybackButtonTitle(for target: AudioPreviewTarget) -> String {
        switch preview.playbackState(for: target) {
        case .paused:
            return "再開"
        case .playing, .stopped:
            return "再生"
        }
    }

    private func waveformPreview(snapshot: AudioPreviewSnapshot, tint: Color, progress: Double) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let points = snapshot.waveform
            let clampedProgress = max(0, min(1, progress))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.08))

                if !points.isEmpty {
                    Canvas { context, size in
                        let step = size.width / CGFloat(max(points.count - 1, 1))
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: size.height / 2))

                        for (index, sample) in points.enumerated() {
                            let x = CGFloat(index) * step
                            let amplitude = CGFloat(sample) * size.height * 0.42
                            path.addLine(to: CGPoint(x: x, y: size.height / 2 - amplitude))
                        }

                        for (index, sample) in points.enumerated().reversed() {
                            let x = CGFloat(index) * step
                            let amplitude = CGFloat(sample) * size.height * 0.42
                            path.addLine(to: CGPoint(x: x, y: size.height / 2 + amplitude))
                        }

                        path.closeSubpath()
                        context.fill(path, with: .color(tint.opacity(0.28)))
                    }
                }

                Rectangle()
                    .fill(tint)
                    .frame(width: 2)
                    .offset(x: width * clampedProgress)
                    .opacity(snapshot.duration > 0 ? 1 : 0)
            }
        }
        .frame(height: 54)
    }

    private var correctionActionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("補正")
                .font(.headline)

            HStack(spacing: 12) {
                Button(job.isProcessing ? "補正中..." : "補正を実行") {
                    startCorrectionProcessing()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(job.inputFile == nil || job.isProcessing || job.isMastering)

                Button("補正後を開く") {
                    guard let outputFile = job.outputFile else { return }
                    NSWorkspace.shared.open(outputFile)
                }
                .disabled(!job.hasExistingOutput || job.isProcessing)

                Button("補正後をFinderで表示") {
                    guard let outputFile = job.outputFile else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([outputFile])
                }
                .disabled(!job.hasExistingOutput || job.isProcessing)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(job.statusMessage)
                        .foregroundStyle(correctionStatusColor)
                    Text(job.isAnalyzingMetrics ? "比較を更新中" : preview.playbackLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var masteringActionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("独立マスタリング")
                .font(.headline)

            HStack(spacing: 12) {
                Button(job.isMastering ? "マスタリング中..." : "マスタリングを実行") {
                    startMasteringProcessing()
                }
                .disabled(!job.hasExistingOutput || job.isMastering || job.isProcessing)

                Button("最終版を開く") {
                    guard let outputFile = job.masteredOutputFile else { return }
                    NSWorkspace.shared.open(outputFile)
                }
                .disabled(!job.hasExistingMasteredOutput || job.isMastering)

                Button("最終版をFinderで表示") {
                    guard let outputFile = job.masteredOutputFile else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([outputFile])
                }
                .disabled(!job.hasExistingMasteredOutput || job.isMastering)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(job.masteringStatusMessage)
                        .foregroundStyle(masteringStatusColor)
                    Text(job.selectedMasteringProfile.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

            comparisonSection(
                title: "入力 -> 補正後",
                inputMetrics: job.inputMetrics,
                outputMetrics: job.outputMetrics,
                emptyMessage: "補正後の比較は、補正を実行すると表示されます。"
            )

            comparisonSection(
                title: "補正後 -> 最終版",
                inputMetrics: job.outputMetrics,
                outputMetrics: job.masteredMetrics,
                emptyMessage: "最終版の比較は、マスタリングを実行すると表示されます。"
            )
        }
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

        Task {
            job.beginProcessing()

            do {
                let outputFile = try await AudioProcessingService().process(inputFile: inputFile) { message in
                    Task { @MainActor in
                        job.appendLog(message)
                    }
                }

                await MainActor.run {
                    job.beginMetricAnalysis()
                }

                async let correctedSnapshotTask: AudioPreviewSnapshot = Task.detached(priority: .utility) {
                    try AudioFileService.makePreviewSnapshot(for: outputFile)
                }.value
                async let correctedMetricsTask: AudioMetricSnapshot = Task.detached(priority: .utility) {
                    try AudioComparisonService.analyze(fileURL: outputFile)
                }.value

                let correctedSnapshot = try await correctedSnapshotTask
                let correctedMetrics = try await correctedMetricsTask

                await MainActor.run {
                    job.finishSuccess(outputFile)
                    preview.preparePreview(for: job.inputFile, target: .input)
                    preview.setPreviewSnapshot(correctedSnapshot, for: .corrected, sourceURL: outputFile)
                    preview.preparePreview(for: nil, target: .mastered)
                    job.finishOutputMetricAnalysis(correctedMetrics)
                }
            } catch {
                await MainActor.run {
                    job.failMetricAnalysis()
                    job.finishFailure(error.localizedDescription)
                }
            }
        }
    }

    private func startMasteringProcessing() {
        guard let correctedFile = job.outputFile else { return }

        Task {
            job.beginMastering()

            do {
                let masteredFile = try await MasteringService().process(
                    inputFile: correctedFile,
                    profile: job.selectedMasteringProfile
                ) { message in
                    Task { @MainActor in
                        job.appendMasteringLog(message)
                    }
                }

                await MainActor.run {
                    job.beginMetricAnalysis()
                }

                async let masteredSnapshotTask: AudioPreviewSnapshot = Task.detached(priority: .utility) {
                    try AudioFileService.makePreviewSnapshot(for: masteredFile)
                }.value
                async let masteredMetricsTask: AudioMetricSnapshot = Task.detached(priority: .utility) {
                    try AudioComparisonService.analyze(fileURL: masteredFile)
                }.value

                let masteredSnapshot = try await masteredSnapshotTask
                let masteredMetrics = try await masteredMetricsTask

                await MainActor.run {
                    job.finishMasteringSuccess(masteredFile)
                    preview.setPreviewSnapshot(masteredSnapshot, for: .mastered, sourceURL: masteredFile)
                    job.finishMasteredMetricAnalysis(masteredMetrics)
                }
            } catch {
                await MainActor.run {
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
        case hertz
        case ratio(Int)
    }

    private func analyzeMetrics(for url: URL, target: MetricTarget) {
        Task {
            await MainActor.run {
                job.beginMetricAnalysis()
            }

            do {
                let metrics = try await Task.detached(priority: .utility) {
                    try AudioComparisonService.analyze(fileURL: url)
                }.value

                await MainActor.run {
                    switch target {
                    case .input:
                        job.finishInputMetricAnalysis(metrics)
                    case .corrected:
                        job.finishOutputMetricAnalysis(metrics)
                    case .mastered:
                        job.finishMasteredMetricAnalysis(metrics)
                    }
                }
            } catch {
                await MainActor.run {
                    job.failMetricAnalysis()
                }
            }
        }
    }

    private func preparePreviewCards() {
        preview.preparePreview(for: job.inputFile, target: .input)
        preview.preparePreview(for: job.hasExistingOutput ? job.outputFile : nil, target: .corrected)
        preview.preparePreview(for: job.hasExistingMasteredOutput ? job.masteredOutputFile : nil, target: .mastered)
    }

    private func formattedValue(_ value: Double, format: MetricFormat) -> String {
        switch format {
        case .dBFS:
            return String(format: "%.2f dB", value)
        case .hertz:
            return String(format: "%.0f Hz", value)
        case .ratio(let decimals):
            return String(format: "%.\(decimals)f", value)
        }
    }

    private func formattedDelta(_ value: Double, format: MetricFormat) -> String {
        switch format {
        case .dBFS:
            return String(format: value >= 0 ? "+%.2f dB" : "%.2f dB", value)
        case .hertz:
            return String(format: value >= 0 ? "+%.0f Hz" : "%.0f Hz", value)
        case .ratio(let decimals):
            return String(format: value >= 0 ? "+%.\(decimals)f" : "%.\(decimals)f", value)
        }
    }
}

#Preview {
    ContentView()
}
