import Foundation
import Testing
@testable import VelouraLucent

struct ContentViewAnalysisLoggingTests {
    @Test(arguments: [false, true])
    @MainActor
    func correctedDisplayAnalysisKeepsResultsAndCompletion(cachedMetrics: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "corrected.wav")
        let channel = (0..<24_000).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / 48_000) * 0.2)
        }
        let signal = AudioSignal(channels: [channel, channel], sampleRate: 48_000)
        try AudioFileService.saveAudio(signal, to: url)
        let storedSignal = try AudioFileService.loadAudio(from: url)
        let expected = MasteringAnalysisService.analyze(signal: storedSignal)
        let job = ProcessingJob()
        let preview = AudioPreviewController()
        let coordinator = DisplayAnalysisCoordinator(job: job, preview: preview)
        defer { coordinator.cancelTasks() }
        let selection = coordinator.beginInputSelection(for: url)
        job.finishSuccess(url)
        if cachedMetrics {
            job.outputMetrics = try AudioComparisonService.analyze(signal: storedSignal)
        }
        var completed = false
        coordinator.startTask(
            for: url,
            target: .corrected,
            selectionID: selection,
            includePreview: false,
            includeMasteringAnalysis: true,
            correctionAnalysisMode: nil,
            onCompletion: { completed = true }
        )
        let deadline = ContinuousClock.now + .seconds(10)
        while !completed, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(completed)
        let actual = try #require(job.outputMasteringAnalysis)
        let metrics = try #require(job.outputMetrics)
        #expect(actual.integratedLoudness == expected.integratedLoudness)
        #expect(actual.truePeakDBFS == expected.truePeakDBFS)
        #expect(actual.loudnessRangeLU == expected.loudnessRangeLU)
        #expect(actual.crestFactorDB == expected.crestFactorDB)
        #expect(Float(metrics.integratedLoudnessLUFS) == expected.integratedLoudness)
        #expect(job.outputNoiseMeasurements != nil)
    }

    @Test
    @MainActor
    func inspectorWindowMinimumWidthsMatchLayoutContract() {
        #expect(WorkspaceLayoutMetrics.sidebarMinimumWidth == 220)
        #expect(WorkspaceLayoutMetrics.sidebarIdealWidth == 260)
        #expect(WorkspaceLayoutMetrics.sidebarMaximumWidth == 300)
        #expect(WorkspaceLayoutMetrics.minimumCenterWidth == 680)
        #expect(WorkspaceLayoutMetrics.inspectorWidth == 480)
        #expect(WorkspaceLayoutMetrics.inspectorVisibleMinimumWindowWidth == 1_500)
        #expect(WorkspaceLayoutMetrics.inspectorHiddenMinimumWindowWidth == 1_500)
        #expect(WorkspaceLayoutMetrics.minimumWindowHeight == 720)
        #expect(WorkspaceLayoutMetrics.recentLogMinimumWidth == 260)
        #expect(WorkspaceLayoutMetrics.workflowMinimumWidth(stageCount: 4) == 260)
        #expect(WorkspaceLayoutMetrics.workflowMinimumWidth(stageCount: 5) == 360)
        #expect(
            WorkspaceLayoutMetrics.recentLogMinimumWidth
                + 22
                + WorkspaceLayoutMetrics.workflowMinimumWidth(stageCount: 5)
                + 36
                <= WorkspaceLayoutMetrics.minimumCenterWidth
        )
        #expect(
            WorkspaceLayoutMetrics.sidebarMaximumWidth
                + WorkspaceLayoutMetrics.minimumCenterWidth
                + WorkspaceLayoutMetrics.inspectorWidth
                < WorkspaceLayoutMetrics.inspectorVisibleMinimumWindowWidth
        )
        #expect(
            WorkspaceLayoutMetrics.sidebarMaximumWidth
                + WorkspaceLayoutMetrics.minimumCenterWidth
                + WorkspaceLayoutMetrics.inspectorWidth
                < WorkspaceLayoutMetrics.inspectorHiddenMinimumWindowWidth
        )
    }

    @Test
    func displayAnalysisMeasurementLogsDuration() async throws {
        let logs = ThreadSafeLogCollector()

        let value = try await DisplayAnalysisSupport.measure("ノイズ測定", logHandler: { message in
            logs.append(message)
        }) {
            42
        }

        #expect(value == 42)
        #expect(logs.values.count == 1)
        #expect(logs.values.first?.hasPrefix("表示解析/計測: ノイズ測定: ") == true)
        #expect(logs.values.first?.hasSuffix("秒") == true)
    }

    @Test
    func disabledOptionalDisplayAnalysisDoesNotLog() async throws {
        let logs = ThreadSafeLogCollector()

        let value: Int? = try await DisplayAnalysisSupport.measureOptional("プレビュー生成", isEnabled: false, logHandler: { message in
            logs.append(message)
        }) {
            Issue.record("Disabled display analysis work should not run")
            return 42
        }

        #expect(value == nil)
        #expect(logs.values.isEmpty)
    }
}

private final class ThreadSafeLogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(message)
    }
}
