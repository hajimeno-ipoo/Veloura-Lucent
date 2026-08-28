import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class ComparisonVideoWindowModel {
    private(set) var launch: ComparisonVideoLaunch?
    var firstSourceID: String?
    var secondSourceID: String?
    var orientation: ComparisonVideoOrientation = .landscape
    var format: ComparisonVideoFormat = .mp4
    var startTime: TimeInterval = 0
    private(set) var selectionWaveform: [WaveformEnvelopeSample] = []
    private(set) var sourceDuration: TimeInterval = 0
    private(set) var outputTime: TimeInterval = 0
    private(set) var isLoading = false
    private(set) var isPreparingPreview = false
    private(set) var isExporting = false
    private(set) var previewPlayer: AVPlayer?
    private(set) var message: String?

    @ObservationIgnored private var selectionTask: Task<Void, Never>?
    @ObservationIgnored private var previewPreparationTask: Task<Void, Never>?
    @ObservationIgnored private var previewClockTask: Task<Void, Never>?
    @ObservationIgnored private var previewFileURL: URL?
    @ObservationIgnored private var previewVideoFileURL: URL?

    var sources: [ComparisonVideoSource] {
        launch?.sources ?? []
    }

    var firstSource: ComparisonVideoSource? {
        sources.first { $0.id == firstSourceID }
    }

    var secondSource: ComparisonVideoSource? {
        sources.first { $0.id == secondSourceID }
    }

    var plan: ComparisonVideoPlan? {
        guard !selectionWaveform.isEmpty else { return nil }
        return ComparisonVideoPlan.make(
            sourceDuration: sourceDuration,
            requestedStartTime: startTime
        )
    }

    var frameState: ComparisonVideoFrameState? {
        guard let firstSource,
              let secondSource,
              let plan else {
            return nil
        }
        return ComparisonVideoFrameState(
            trackTitle: firstSource.trackTitle,
            firstRoleTitle: firstSource.roleTitle,
            secondRoleTitle: secondSource.roleTitle,
            plan: plan,
            outputTime: min(outputTime, plan.outputDuration)
        )
    }

    var canExport: Bool {
        frameState != nil && !isLoading && !isPreparingPreview && !isExporting
    }

    func configure(with launch: ComparisonVideoLaunch?) {
        previewPreparationTask?.cancel()
        stopAndDiscardPreview()
        selectionTask?.cancel()
        self.launch = launch
        firstSourceID = nil
        secondSourceID = nil
        selectionWaveform = []
        sourceDuration = 0
        startTime = 0
        isLoading = false
        isPreparingPreview = false
        orientation = .landscape
        format = .mp4
        message = launch == nil ? "現在のモードに比較できる音源がありません。" : nil
    }

    func selectionDidChange() {
        stopAndDiscardPreview()
        selectionTask?.cancel()
        selectionWaveform = []
        sourceDuration = 0
        startTime = 0
        isLoading = false
        message = nil

        guard let firstSource, let secondSource else { return }
        guard firstSource.id != secondSource.id else {
            message = "異なる音源を選択してください。"
            return
        }

        isLoading = true
        selectionTask = Task { [weak self] in
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    guard firstSource.matchesCurrentFile,
                          secondSource.matchesCurrentFile else {
                        throw ComparisonVideoExportError.sourceUnavailable
                    }
                    let firstInfo = try AudioFileService.fileInfo(for: firstSource.fileURL)
                    let secondInfo = try AudioFileService.fileInfo(for: secondSource.fileURL)
                    guard abs(firstInfo.duration - secondInfo.duration)
                            <= 1 / min(firstInfo.sampleRate, secondInfo.sampleRate) else {
                        throw ComparisonVideoExportError.incompatibleSources
                    }
                    let waveform = try ComparisonVideoExportService().makeSelectionWaveform(
                        for: firstSource,
                        bucketCount: 512
                    )
                    return (waveform, firstInfo.duration)
                }.value
                guard !Task.isCancelled else { return }
                self?.selectionWaveform = loaded.0
                self?.sourceDuration = loaded.1
                self?.message = nil
                self?.preparePreview()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.message = error.localizedDescription
            }
            self?.isLoading = false
        }
    }

    func setStartTime(_ value: TimeInterval) {
        guard sourceDuration > 0 else { return }
        let usableDuration = min(ComparisonVideoPlan.maximumOutputDuration, sourceDuration)
        startTime = min(max(value, 0), max(sourceDuration - usableDuration, 0))
        stopAndDiscardPreview()
        preparePreview(after: .milliseconds(250))
    }

    func stopPreview() {
        previewPlayer?.pause()
        previewPlayer?.seek(to: .zero)
        outputTime = 0
    }

    func export(to destinationURL: URL) {
        guard let request = makeExportRequest(destinationURL: destinationURL) else { return }
        stopPreview()
        isExporting = true
        message = nil
        Task { [weak self] in
            do {
                try await ComparisonVideoExportService().export(request)
                self?.message = "動画を書き出しました。"
            } catch {
                self?.message = error.localizedDescription
            }
            self?.isExporting = false
        }
    }

    func makeExportRequest(destinationURL: URL) -> ComparisonVideoExportRequest? {
        guard let firstSource,
              let secondSource,
              plan != nil else {
            return nil
        }
        return ComparisonVideoExportRequest(
            first: firstSource,
            second: secondSource,
            startTime: startTime,
            orientation: orientation,
            format: format,
            destinationURL: destinationURL
        )
    }

    func suggestedFileName() -> String? {
        guard let firstSource, let secondSource else { return nil }
        return ComparisonVideoSourceCatalog.suggestedFileName(
            first: firstSource,
            second: secondSource,
            format: format
        )
    }

    func close() {
        selectionTask?.cancel()
        previewPreparationTask?.cancel()
        stopAndDiscardPreview()
    }

    private func preparePreview(after delay: Duration? = nil) {
        guard let firstSource, let secondSource else { return }
        let requestedStartTime = startTime
        isPreparingPreview = true
        message = nil
        previewPreparationTask?.cancel()
        previewPreparationTask = Task { [weak self] in
            var pendingPreviewFiles: [URL] = []
            if let delay {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            do {
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try ComparisonVideoExportService().prepareAudio(
                        first: firstSource,
                        second: secondSource,
                        startTime: requestedStartTime
                    )
                }.value
                guard !Task.isCancelled else { return }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("VelouraComparisonPreview-\(UUID().uuidString)")
                    .appendingPathExtension("wav")
                let videoURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("VelouraComparisonPreviewVideo-\(UUID().uuidString)")
                    .appendingPathExtension("mov")
                pendingPreviewFiles = [url, videoURL]
                try ComparisonVideoExportService().writePreparedAudio(prepared, to: url)
                try await ComparisonVideoExportService().writePreviewVideo(
                    duration: prepared.plan.outputDuration,
                    to: videoURL
                )
                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: url)
                    try? FileManager.default.removeItem(at: videoURL)
                    return
                }
                guard let self else {
                    try? FileManager.default.removeItem(at: url)
                    try? FileManager.default.removeItem(at: videoURL)
                    return
                }
                let player = try await self.makePreviewPlayer(
                    audioURL: url,
                    videoURL: videoURL,
                    duration: prepared.plan.outputDuration
                )
                self.discardPreviewFile()
                self.previewFileURL = url
                self.previewVideoFileURL = videoURL
                self.previewPlayer = player
                pendingPreviewFiles.removeAll()
                self.outputTime = 0
                self.startPreviewClock()
            } catch is CancellationError {
                pendingPreviewFiles.forEach { try? FileManager.default.removeItem(at: $0) }
                return
            } catch {
                pendingPreviewFiles.forEach { try? FileManager.default.removeItem(at: $0) }
                self?.message = error.localizedDescription
            }
            self?.isPreparingPreview = false
        }
    }

    private func startPreviewClock() {
        previewClockTask?.cancel()
        previewClockTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.previewPlayer else { return }
                let seconds = player.currentTime().seconds
                if seconds.isFinite {
                    self.outputTime = min(max(seconds, 0), self.plan?.outputDuration ?? seconds)
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func stopAndDiscardPreview() {
        previewPreparationTask?.cancel()
        previewPreparationTask = nil
        isPreparingPreview = false
        stopPreview()
        previewClockTask?.cancel()
        previewClockTask = nil
        previewPlayer = nil
        discardPreviewFile()
    }

    private func discardPreviewFile() {
        if let previewFileURL {
            try? FileManager.default.removeItem(at: previewFileURL)
        }
        previewFileURL = nil
        if let previewVideoFileURL {
            try? FileManager.default.removeItem(at: previewVideoFileURL)
        }
        previewVideoFileURL = nil
    }

    private func makePreviewPlayer(
        audioURL: URL,
        videoURL: URL,
        duration: TimeInterval
    ) async throws -> AVPlayer {
        let audioAsset = AVURLAsset(url: audioURL)
        let videoAsset = AVURLAsset(url: videoURL)
        guard let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw ComparisonVideoExportError.audioPreparationFailed
        }
        let composition = AVMutableComposition()
        guard let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ComparisonVideoExportError.writerConfigurationFailed
        }
        let timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
        try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        return AVPlayer(playerItem: AVPlayerItem(asset: composition))
    }
}
