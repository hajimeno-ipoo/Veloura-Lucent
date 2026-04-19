import AppKit
import SwiftUI

struct PreviewPanelView: View {
    let preview: AudioPreviewController
    let inputFileURL: URL?
    let correctedFileURL: URL?
    let masteredFileURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("試聴比較")
                    .font(.headline)
                Spacer()
                Text(preview.playbackLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            comparisonControlSection

            HStack(spacing: 14) {
                previewCard(title: "入力音声", target: .input, fileURL: inputFileURL, tint: .blue)
                previewCard(title: "補正後", target: .corrected, fileURL: correctedFileURL, tint: .green)
                previewCard(title: "最終版", target: .mastered, fileURL: masteredFileURL, tint: .orange)
            }
        }
    }

    private var comparisonControlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("比較対象", selection: binding(
                    get: { preview.comparisonPair },
                    set: { preview.setComparisonPair($0) }
                )) {
                    ForEach(AudioComparisonPair.allCases) { pair in
                        Text(pair.title).tag(pair)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()
            }

            HStack(spacing: 10) {
                Text(preview.comparisonPair.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 8) {
                    Text("vol.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: binding(
                            get: { Double(preview.playbackVolume) },
                            set: { preview.setPlaybackVolume(Float($0)) }
                        ),
                        in: 0 ... 1,
                        step: 0.01
                    )
                    .frame(width: 120)
                    Text("\(Int((preview.playbackVolume * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }

                Toggle(
                    "ラウドネス合わせ比較",
                    isOn: binding(
                        get: { preview.isLoudnessMatchedComparisonEnabled },
                        set: { preview.setLoudnessMatchedComparisonEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)

                Text("現在: \(preview.comparisonPair.title(for: preview.activeComparisonSide))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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

    private func previewCard(title: String, target: AudioPreviewTarget, fileURL: URL?, tint: Color) -> some View {
        let snapshot = preview.snapshot(for: target)
        let liveBands = preview.liveBandLevels[target] ?? AudioBandCatalog.previewBands.map {
            LiveBandSample(id: $0.id, label: $0.label, level: 0)
        }
        let isActive = preview.activeTarget == target
        let comparisonSide = preview.comparisonSide(for: target)
        let playbackState = preview.playbackState(for: target)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                if let comparisonSide, preview.isInComparisonPair(target) {
                    Text(preview.comparisonPair.title(for: comparisonSide))
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(isActive ? tint.opacity(0.22) : Color.secondary.opacity(0.12)))
                }
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
