import AppKit
import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class ComparisonVideoWindowModel {
    private(set) var launch: ComparisonVideoLaunch?
    var firstSourceID: String?
    var secondSourceID: String?
    var orientation: ComparisonVideoOrientation = .landscape {
        didSet {
            guard orientation != oldValue else { return }
            displaySettings.updateInspectorDefaultPosition(
                from: oldValue,
                to: orientation
            )
            guard !hasExplicitInspectorAspectRatio else { return }
            displaySettings.setInspectorAspectRatio(
                orientation == .landscape ? .custom : .portrait,
                for: orientation
            )
        }
    }
    var format: ComparisonVideoFormat = .mp4
    var startTime: TimeInterval = 0
    var displaySettings = ComparisonVideoDisplaySettings(
        trackTitle: "",
        firstRoleTitle: "",
        secondRoleTitle: ""
    )
    private(set) var selectionWaveform: [WaveformEnvelopeSample] = []
    private(set) var sourceDuration: TimeInterval = 0
    private(set) var outputTime: TimeInterval = 0
    private(set) var previewFrameTime: TimeInterval = 0
    private(set) var previewSpectrumTimeline: [ComparisonVideoSpectrumFrame] = []
    private(set) var isLoading = false
    private(set) var isPreparingPreview = false
    private(set) var isExporting = false
    private(set) var isPreviewPlaying = false
    private(set) var previewPlayer: AVPlayer?
    private(set) var previewVolume: Double = 1
    private(set) var message: String?
    private(set) var selectedFileInfoBySourceID: [String: AudioFileInfo] = [:]

    @ObservationIgnored private var selectionTask: Task<Void, Never>?
    @ObservationIgnored private var previewPreparationTask: Task<Void, Never>?
    @ObservationIgnored private var previewClockTask: Task<Void, Never>?
    @ObservationIgnored private var previewFileURL: URL?
    @ObservationIgnored private var hasExplicitInspectorAspectRatio = false

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
            displaySettings: displaySettings,
            firstInspectorInfo: inspectorInfo(for: firstSource),
            secondInspectorInfo: inspectorInfo(for: secondSource),
            plan: plan,
            outputTime: min(previewFrameTime, plan.outputDuration),
            effectsTime: min(outputTime, plan.outputDuration),
            visualizerSpectrum: spectrumFrame(at: outputTime)
        )
    }

    var inspectorSize: CGSize {
        displaySettings.inspectorSize(for: orientation)
    }

    var inspectorScale: Double {
        displaySettings.inspectorScale(for: orientation)
    }

    var inspectorScaleRange: ClosedRange<Double> {
        displaySettings.inspectorScaleRange(for: orientation)
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
        previewFrameTime = 0
        previewSpectrumTimeline = []
        selectedFileInfoBySourceID = [:]
        isLoading = false
        isPreparingPreview = false
        hasExplicitInspectorAspectRatio = false
        orientation = .landscape
        format = .mp4
        displaySettings = ComparisonVideoDisplaySettings(
            trackTitle: launch?.sources.first?.trackTitle ?? "",
            firstRoleTitle: "",
            secondRoleTitle: ""
        )
        message = launch == nil ? "現在のモードに比較できる音源がありません。" : nil
    }

    func selectionDidChange() {
        stopAndDiscardPreview()
        selectionTask?.cancel()
        selectionWaveform = []
        sourceDuration = 0
        startTime = 0
        selectedFileInfoBySourceID = [:]
        isLoading = false
        message = nil

        if let firstSource {
            displaySettings.trackTitle = firstSource.trackTitle
            displaySettings.firstRoleTitle = firstSource.roleTitle
        }
        if let secondSource {
            displaySettings.secondRoleTitle = secondSource.roleTitle
        }

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
                    return (waveform, firstInfo, secondInfo)
                }.value
                guard !Task.isCancelled else { return }
                self?.selectionWaveform = loaded.0
                self?.sourceDuration = loaded.1.duration
                self?.selectedFileInfoBySourceID = [
                    firstSource.id: loaded.1,
                    secondSource.id: loaded.2,
                ]
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

    func setDisplayPosition(_ position: CGPoint, for element: ComparisonVideoEditableElement) {
        displaySettings.setPosition(position, for: element)
    }

    func setInspectorAspectRatio(_ aspectRatio: ComparisonVideoInspectorAspectRatio) {
        hasExplicitInspectorAspectRatio = true
        displaySettings.setInspectorAspectRatio(aspectRatio, for: orientation)
    }

    func setCustomInspectorAspectWidth(_ value: Double) {
        hasExplicitInspectorAspectRatio = true
        displaySettings.setCustomAspectWidth(value, for: orientation)
    }

    func setCustomInspectorAspectHeight(_ value: Double) {
        hasExplicitInspectorAspectRatio = true
        displaySettings.setCustomAspectHeight(value, for: orientation)
    }

    func setInspectorScale(_ value: Double) {
        displaySettings.setInspectorScale(value, for: orientation)
    }

    func setFadeInDuration(_ value: Double) {
        displaySettings.fadeInDuration = value
        refreshPreviewAudio()
    }

    func setFadeOutDuration(_ value: Double) {
        displaySettings.fadeOutDuration = value
        refreshPreviewAudio()
    }

    func setVideoFadeInEnabled(_ isEnabled: Bool) {
        displaySettings.videoFadeInEnabled = isEnabled
    }

    func setVideoFadeOutEnabled(_ isEnabled: Bool) {
        displaySettings.videoFadeOutEnabled = isEnabled
    }

    func setAudioFadeInEnabled(_ isEnabled: Bool) {
        displaySettings.audioFadeInEnabled = isEnabled
        refreshPreviewAudio()
    }

    func setAudioFadeOutEnabled(_ isEnabled: Bool) {
        displaySettings.audioFadeOutEnabled = isEnabled
        refreshPreviewAudio()
    }

    func setVisualizerResponse(_ value: Double) {
        displaySettings.visualizerResponse = value
        refreshPreviewSpectrumTimeline()
    }

    func setVisualizerLeadingColor(_ color: NSColor) {
        guard let color = rgbaColor(from: color) else { return }
        displaySettings.visualizerLeadingColor = color
    }

    func setVisualizerCenterColor(_ color: NSColor) {
        guard let color = rgbaColor(from: color) else { return }
        displaySettings.visualizerCenterColor = color
    }

    func setVisualizerTrailingColor(_ color: NSColor) {
        guard let color = rgbaColor(from: color) else { return }
        displaySettings.visualizerTrailingColor = color
    }

    func setBackgroundColor(_ color: NSColor) {
        guard let color = rgbaColor(from: color) else { return }
        displaySettings.backgroundColor = color
    }

    func setTitleColor(_ color: NSColor) {
        guard let color = rgbaColor(from: color) else { return }
        displaySettings.titleColor = color
    }

    func setFirstRoleColor(_ color: NSColor) {
        guard let color = rgbaColor(from: color) else { return }
        displaySettings.firstRoleColor = color
    }

    func setSecondRoleColor(_ color: NSColor) {
        guard let color = rgbaColor(from: color) else { return }
        displaySettings.secondRoleColor = color
    }

    func setBackgroundImage(from fileURL: URL) {
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        guard let data = try? Data(contentsOf: fileURL),
              let image = NSImage(data: data) else {
            message = "背景画像を読み込めませんでした。"
            return
        }
        displaySettings.backgroundImage = ComparisonVideoBackgroundImage(
            image: image,
            fileName: fileURL.lastPathComponent
        )
        message = nil
    }

    func clearBackgroundImage() {
        displaySettings.backgroundImage = nil
    }

    func stopPreview() {
        previewPlayer?.pause()
        previewPlayer?.seek(to: .zero)
        isPreviewPlaying = false
        outputTime = 0
        previewFrameTime = 0
    }

    func togglePreviewPlayback() {
        guard let previewPlayer else { return }
        if isPreviewPlaying {
            previewPlayer.pause()
            isPreviewPlaying = false
            return
        }

        if let duration = plan?.outputDuration,
           outputTime >= max(duration - 0.05, 0) {
            seekPreview(to: 0)
        }
        previewPlayer.play()
        isPreviewPlaying = true
    }

    func seekPreview(to time: TimeInterval) {
        guard let previewPlayer else { return }
        let duration = plan?.outputDuration ?? 0
        let clampedTime = min(max(time, 0), duration)
        previewPlayer.seek(
            to: CMTime(seconds: clampedTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        updatePreviewTimes(to: clampedTime)
    }

    func setPreviewVolume(_ volume: Double) {
        let clampedVolume = min(max(volume.isFinite ? volume : 1, 0), 1)
        previewVolume = clampedVolume
        previewPlayer?.volume = Float(clampedVolume)
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
            displaySettings: displaySettings,
            firstInspectorInfo: inspectorInfo(for: firstSource),
            secondInspectorInfo: inspectorInfo(for: secondSource),
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
        let requestedDisplaySettings = displaySettings
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
                        startTime: requestedStartTime,
                        displaySettings: requestedDisplaySettings
                    )
                }.value
                guard !Task.isCancelled else { return }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("VelouraComparisonPreview-\(UUID().uuidString)")
                    .appendingPathExtension("wav")
                pendingPreviewFiles = [url]
                try ComparisonVideoExportService().writePreparedAudio(prepared, to: url)
                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                guard let self else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                let player = AVPlayer(url: url)
                self.discardPreviewFile()
                self.previewFileURL = url
                player.volume = Float(self.previewVolume)
                self.previewPlayer = player
                pendingPreviewFiles.removeAll()
                self.outputTime = 0
                self.previewFrameTime = 0
                if requestedDisplaySettings.visualizerResponse
                    == self.displaySettings.visualizerResponse
                {
                    self.previewSpectrumTimeline = prepared.spectrumTimeline
                } else {
                    self.refreshPreviewSpectrumTimeline()
                }
                self.isPreviewPlaying = false
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
                    let outputTime = min(max(seconds, 0), self.plan?.outputDuration ?? seconds)
                    self.updatePreviewTimes(to: outputTime)
                }
                let isPlaying = player.timeControlStatus == .playing
                if self.isPreviewPlaying != isPlaying {
                    self.isPreviewPlaying = isPlaying
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func updatePreviewTimes(to time: TimeInterval) {
        if outputTime != time {
            outputTime = time
        }
        let frameTime = plan?.previewFrameTime(at: time) ?? time
        if previewFrameTime != frameTime {
            previewFrameTime = frameTime
        }
    }

    private func spectrumFrame(at time: TimeInterval) -> ComparisonVideoSpectrumFrame {
        ComparisonVideoPreparedAudio.spectrumFrame(
            in: previewSpectrumTimeline,
            at: time
        )
    }

    private func refreshPreviewAudio() {
        guard firstSource != nil, secondSource != nil, plan != nil else { return }
        previewPlayer?.pause()
        isPreviewPlaying = false
        preparePreview(after: .milliseconds(250))
    }

    private func refreshPreviewSpectrumTimeline() {
        guard let firstSource,
              let secondSource,
              let plan else { return }
        previewSpectrumTimeline = ComparisonVideoExportService.makeSpectrumTimeline(
            first: firstSource.spectrogram,
            second: secondSource.spectrogram,
            plan: plan,
            displaySettings: displaySettings
        )
    }

    private func inspectorInfo(for source: ComparisonVideoSource) -> ComparisonVideoInspectorInfo {
        ComparisonVideoInspectorInfo(
            metrics: source.inspectorMetrics,
            fileInfo: selectedFileInfoBySourceID[source.id]
        )
    }

    private func rgbaColor(from color: NSColor) -> ComparisonVideoRGBAColor? {
        guard let converted = color.usingColorSpace(.sRGB) else { return nil }
        return ComparisonVideoRGBAColor(
            red: converted.redComponent,
            green: converted.greenComponent,
            blue: converted.blueComponent,
            alpha: converted.alphaComponent
        )
    }

    private func stopAndDiscardPreview() {
        previewPreparationTask?.cancel()
        previewPreparationTask = nil
        isPreparingPreview = false
        stopPreview()
        previewClockTask?.cancel()
        previewClockTask = nil
        previewPlayer = nil
        previewSpectrumTimeline = []
        discardPreviewFile()
    }

    private func discardPreviewFile() {
        if let previewFileURL {
            try? FileManager.default.removeItem(at: previewFileURL)
        }
        previewFileURL = nil
    }
}
