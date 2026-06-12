import AppKit
import SwiftUI

struct PreviewPanelView: View {
    let preview: AudioPreviewController
    let inputFileURL: URL?
    let correctedFileURL: URL?
    let masteredFileURL: URL?
    let completionReport: CompletionReport?
    @State private var isCompletionReportPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("試聴比較")
                    .font(.headline)
                Spacer()
                Button("完了後レポート") {
                    isCompletionReportPresented = true
                }
                .disabled(completionReport == nil)
                .popover(isPresented: $isCompletionReportPresented, arrowEdge: .bottom) {
                    if let completionReport {
                        CompletionReportPopoverView(report: completionReport)
                    }
                }
                Text(preview.playbackLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            comparisonControlSection

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: 14)],
                alignment: .leading,
                spacing: 14
            ) {
                PreviewCardView(
                    title: "入力音声",
                    state: preview.cardState(for: .input),
                    fileURL: inputFileURL,
                    tint: .blue,
                    isActive: preview.activeTarget == .input,
                    comparisonBadge: comparisonBadge(for: .input),
                    onPlay: { preview.startPlayback(for: inputFileURL, target: .input) },
                    onPause: { preview.pausePlayback(target: .input) },
                    onStop: { preview.stopPlayback(target: .input) }
                )
                PreviewCardView(
                    title: "補正後",
                    state: preview.cardState(for: .corrected),
                    fileURL: correctedFileURL,
                    tint: .green,
                    isActive: preview.activeTarget == .corrected,
                    comparisonBadge: comparisonBadge(for: .corrected),
                    onPlay: { preview.startPlayback(for: correctedFileURL, target: .corrected) },
                    onPause: { preview.pausePlayback(target: .corrected) },
                    onStop: { preview.stopPlayback(target: .corrected) }
                )
                PreviewCardView(
                    title: "最終版",
                    state: preview.cardState(for: .mastered),
                    fileURL: masteredFileURL,
                    tint: .orange,
                    isActive: preview.activeTarget == .mastered,
                    comparisonBadge: comparisonBadge(for: .mastered),
                    onPlay: { preview.startPlayback(for: masteredFileURL, target: .mastered) },
                    onPause: { preview.pausePlayback(target: .mastered) },
                    onStop: { preview.stopPlayback(target: .mastered) }
                )
            }
        }
    }

    private var comparisonControlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("比較対象", selection: binding(
                get: { preview.comparisonPair },
                set: { preview.setComparisonPair($0) }
            )) {
                ForEach(AudioComparisonPair.allCases) { pair in
                    Text(pair.title).tag(pair)
                }
            }
            .pickerStyle(.segmented)

            Text(preview.comparisonPair.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    volumeControl
                    loudnessComparisonToggle
                    activeComparisonLabel
                }

                VStack(alignment: .leading, spacing: 10) {
                    volumeControl
                    loudnessComparisonToggle
                    activeComparisonLabel
                }
            }

            HStack(spacing: 10) {
                Button("Aを再生") {
                    preview.playComparisonSide(.a)
                }
                .disabled(comparisonFileURL(for: .a) == nil)

                Button("Bを再生") {
                    preview.playComparisonSide(.b)
                }
                .disabled(comparisonFileURL(for: .b) == nil)

                Button("A/B切替") {
                    preview.toggleComparisonSide()
                }
                .disabled(comparisonFileURL(for: .a) == nil || comparisonFileURL(for: .b) == nil)
            }
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 8) {
            Text("音量")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Slider(
                value: binding(
                    get: { Double(preview.playbackVolume) },
                    set: { preview.setPlaybackVolume(Float($0)) }
                ),
                in: 0 ... 1,
                step: 0.01
            )
            .frame(minWidth: 100, idealWidth: 140, maxWidth: 180)
            Text("\(Int((preview.playbackVolume * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private var loudnessComparisonToggle: some View {
        Toggle(
            "ラウドネス合わせ比較",
            isOn: binding(
                get: { preview.isLoudnessMatchedComparisonEnabled },
                set: { preview.setLoudnessMatchedComparisonEnabled($0) }
            )
        )
        .toggleStyle(.switch)
        .controlSize(.small)
        .fixedSize()
    }

    private var activeComparisonLabel: some View {
        Text("現在: \(preview.comparisonPair.title(for: preview.activeComparisonSide))")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private func comparisonBadge(for target: AudioPreviewTarget) -> String? {
        let comparisonSide = preview.comparisonSide(for: target)
        guard let comparisonSide, preview.isInComparisonPair(target) else { return nil }
        return preview.comparisonPair.title(for: comparisonSide)
    }

    private func comparisonFileURL(for side: AudioComparisonSide) -> URL? {
        switch preview.comparisonTarget(for: side) {
        case .input:
            return inputFileURL
        case .corrected:
            return correctedFileURL
        case .mastered:
            return masteredFileURL
        }
    }

    private func binding<Value>(get: @escaping @MainActor () -> Value, set: @escaping @MainActor (Value) -> Void) -> Binding<Value> {
        Binding(
            get: { @MainActor in get() },
            set: { @MainActor newValue in set(newValue) }
        )
    }
}

private struct CompletionReportPopoverView: View {
    let report: CompletionReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("完了後レポート")
                        .font(.title3.weight(.bold))
                    Spacer()
                    Text(severityText(report.severity))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(severityColor(report.severity))
                }

                reportSection(title: "音量とピーク", rows: report.loudnessRows)
                reportSection(title: "ノイズ", rows: report.noiseRows)
                reportSection(title: "高域保持", rows: report.highFrequencyRows)

                Text(report.reminder)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(18)
        }
        .frame(width: 540, height: 620)
    }

    private func reportSection(title: String, rows: [CompletionReportRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(severityColor(row.severity))
                        .frame(width: 8, height: 8)
                        .padding(.top, 7)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.title)
                                .font(.body.weight(.semibold))
                            Spacer()
                            Text(row.value)
                                .font(.body.monospacedDigit().weight(.semibold))
                                .foregroundStyle(severityColor(row.severity))
                        }
                        Text(row.detail)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func severityText(_ severity: CompletionReportSeverity) -> String {
        switch severity {
        case .normal:
            return "確認"
        case .caution:
            return "注意"
        case .warning:
            return "警告"
        }
    }

    private func severityColor(_ severity: CompletionReportSeverity) -> Color {
        switch severity {
        case .normal:
            return .green
        case .caution:
            return .orange
        case .warning:
            return .red
        }
    }
}

private struct PreviewCardView: View {
    let title: String
    let state: AudioPreviewCardState
    let fileURL: URL?
    let tint: Color
    let isActive: Bool
    let comparisonBadge: String?
    let onPlay: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void

    var body: some View {
        let snapshot = state.snapshot ?? emptySnapshot
        let liveBands = state.liveBandLevels.isEmpty
            ? AudioBandCatalog.previewBands.map { LiveBandSample(id: $0.id, label: $0.label, level: 0) }
            : state.liveBandLevels
        let playbackState = state.playbackState

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                if let comparisonBadge {
                    Text(comparisonBadge)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(isActive ? tint.opacity(0.22) : Color.secondary.opacity(0.12)))
                }
                Spacer()
                Text(playbackTimeText(snapshot: snapshot))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(fileURL?.lastPathComponent ?? "まだ確認できません")
                .lineLimit(2)
                .foregroundStyle(fileURL == nil ? .secondary : .primary)

            waveformPreview(snapshot: snapshot, tint: tint, progress: state.playbackProgress)

            VStack(spacing: 6) {
                ForEach(liveBands) { band in
                    HStack(spacing: 8) {
                        Text(band.label)
                            .font(.caption)
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

            ViewThatFits(in: .horizontal) {
                playbackButtons(playbackState: playbackState, compact: false)
                playbackButtons(playbackState: playbackState, compact: true)
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

    @ViewBuilder
    private func playbackButtons(playbackState: AudioPlaybackState, compact: Bool) -> some View {
        HStack(spacing: 8) {
            if compact {
                Button("再生", systemImage: "play.fill", action: onPlay)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(primaryPlaybackButtonTitle(for: playbackState))
                    .help(primaryPlaybackButtonTitle(for: playbackState))
                    .disabled(fileURL == nil || playbackState == .playing)

                Button("一時停止", systemImage: "pause.fill", action: onPause)
                    .labelStyle(.iconOnly)
                    .help("一時停止")
                    .disabled(playbackState != .playing)

                Button("停止", systemImage: "stop.fill", action: onStop)
                    .labelStyle(.iconOnly)
                    .help("停止")
                    .disabled(fileURL == nil || playbackState == .stopped)

                if let fileURL {
                    Button("Finderに表示", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }
                    .labelStyle(.iconOnly)
                    .help("Finderに表示")
                }
            } else {
                Button(primaryPlaybackButtonTitle(for: playbackState), systemImage: "play.fill", action: onPlay)
                    .disabled(fileURL == nil || playbackState == .playing)

                Button("一時停止", systemImage: "pause.fill", action: onPause)
                    .disabled(playbackState != .playing)

                Button("停止", systemImage: "stop.fill", action: onStop)
                    .disabled(fileURL == nil || playbackState == .stopped)

                if let fileURL {
                    Button("Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }
                }
            }
        }
    }

    private var emptySnapshot: AudioPreviewSnapshot {
        AudioPreviewSnapshot(
            waveform: Array(repeating: 0, count: AudioFileService.previewBucketCount),
            duration: 0,
            bandLevels: Dictionary(uniqueKeysWithValues: AudioBandCatalog.previewBands.map { ($0.id, Array(repeating: 0, count: AudioFileService.previewBucketCount)) }),
            bandLevelDBs: Dictionary(uniqueKeysWithValues: AudioBandCatalog.previewBands.map { ($0.id, Array(repeating: Float(-120), count: AudioFileService.previewBucketCount)) })
        )
    }

    private func primaryPlaybackButtonTitle(for playbackState: AudioPlaybackState) -> String {
        switch playbackState {
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

    private func playbackTimeText(snapshot: AudioPreviewSnapshot) -> String {
        guard snapshot.duration > 0 else {
            return "--:-- / --:--"
        }
        return "\(format(duration: state.playbackPosition)) / \(format(duration: snapshot.duration))"
    }

    private func format(duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
