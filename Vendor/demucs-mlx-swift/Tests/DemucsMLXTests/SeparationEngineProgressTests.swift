@testable import DemucsMLX
import Foundation
import Testing

private struct RecordedProgress: Sendable {
    let fraction: Float
    let stage: String
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEntries: [RecordedProgress] = []

    var entries: [RecordedProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storedEntries
    }

    func append(fraction: Float, stage: String) {
        lock.lock()
        storedEntries.append(RecordedProgress(fraction: fraction, stage: stage))
        lock.unlock()
    }
}

private final class PredictCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCount
    }

    func increment() {
        lock.lock()
        storedCount += 1
        lock.unlock()
    }
}

private struct RecordedModelInput: Sendable {
    let samples: [Float]
    let frames: Int
}

private final class ModelInputRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedInputs: [RecordedModelInput] = []

    var inputs: [RecordedModelInput] {
        lock.lock()
        defer { lock.unlock() }
        return storedInputs
    }

    func append(samples: [Float], frames: Int) {
        lock.lock()
        storedInputs.append(RecordedModelInput(samples: samples, frames: frames))
        lock.unlock()
    }
}

private struct ProgressReportingModel: StemSeparationModel {
    let descriptor: DemucsModelDescriptor
    let reportedFractions: [Float]
    let cancelDuringPrediction: Bool
    let callCounter: PredictCallCounter

    init(
        reportedFractions: [Float],
        defaultSegmentSeconds: Double = 1,
        cancelDuringPrediction: Bool = false,
        callCounter: PredictCallCounter = PredictCallCounter()
    ) {
        descriptor = DemucsModelDescriptor(
            name: "progress-test",
            sourceNames: ["source"],
            sampleRate: 100,
            audioChannels: 1,
            defaultSegmentSeconds: defaultSegmentSeconds
        )
        self.reportedFractions = reportedFractions
        self.cancelDuringPrediction = cancelDuringPrediction
        self.callCounter = callCounter
    }

    func predict(
        batchData: [Float],
        batchSize: Int,
        channels: Int,
        frames: Int,
        monitor: SeparationMonitor?
    ) throws -> [Float] {
        callCounter.increment()
        for fraction in reportedFractions {
            monitor?.reportProgress(fraction, stage: "model-\(fraction)")
        }
        if cancelDuringPrediction {
            monitor?.cancelToken?.cancel()
            try monitor?.checkCancellation()
        }
        return [Float](repeating: 0, count: batchSize * channels * frames)
    }
}

private struct InputEchoModel: StemSeparationModel {
    let descriptor = DemucsModelDescriptor(
        name: "shift-input-test",
        sourceNames: ["source"],
        sampleRate: 100,
        audioChannels: 1,
        defaultSegmentSeconds: 1
    )
    let recorder: ModelInputRecorder

    func predict(
        batchData: [Float],
        batchSize: Int,
        channels: Int,
        frames: Int,
        monitor: SeparationMonitor?
    ) throws -> [Float] {
        recorder.append(samples: batchData, frames: frames)
        return batchData
    }
}

private func makeMonitor(
    recorder: ProgressRecorder,
    cancelToken: DemucsCancelToken? = nil
) -> SeparationMonitor {
    SeparationMonitor(
        cancelToken: cancelToken,
        progressHandler: { fraction, stage in
            recorder.append(fraction: fraction, stage: stage)
        }
    )
}

private func expectMonotonicUnitProgress(_ entries: [RecordedProgress]) {
    #expect(!entries.isEmpty)
    for entry in entries {
        #expect(entry.fraction >= 0)
        #expect(entry.fraction <= 1)
    }
    for pair in zip(entries, entries.dropFirst()) {
        #expect(pair.0.fraction <= pair.1.fraction)
    }
}

@Test("Each shift occupies its own global progress slice")
func eachShiftOccupiesItsOwnGlobalProgressSlice() throws {
    let recorder = ProgressRecorder()
    let counter = PredictCallCounter()
    let model = ProgressReportingModel(
        reportedFractions: [0, 0.5, 1],
        callCounter: counter
    )
    let engine = SeparationEngine(
        model: model,
        parameters: DemucsSeparationParameters(
            shifts: 3,
            overlap: 0,
            split: false,
            segmentSeconds: 1,
            batchSize: 1,
            seed: 7
        ),
        monitor: makeMonitor(recorder: recorder)
    )

    _ = try engine.separate(mix: [0, 0, 0, 0], channels: 1, frames: 4, sampleRate: 100)

    let modelCompletions = recorder.entries
        .filter { $0.stage == "model-1.0" }
        .map(\.fraction)
    #expect(counter.count == 3)
    #expect(modelCompletions.count == 3)
    #expect(abs(modelCompletions[0] - (1.0 / 3.0)) < 0.000_001)
    #expect(abs(modelCompletions[1] - (2.0 / 3.0)) < 0.000_001)
    #expect(abs(modelCompletions[2] - 1.0) < 0.000_001)
    expectMonotonicUnitProgress(recorder.entries)
}

@Test("One shift uses reference zero padding and inverse crop")
func oneShiftUsesReferenceZeroPaddingAndInverseCrop() throws {
    let recorder = ModelInputRecorder()
    let input: [Float] = [0.25, -0.5, 0.75, -1]
    let engine = SeparationEngine(
        model: InputEchoModel(recorder: recorder),
        parameters: DemucsSeparationParameters(
            shifts: 1,
            overlap: 0,
            split: false,
            segmentSeconds: 1,
            batchSize: 1,
            seed: 7
        ),
        monitor: nil
    )

    let output = try engine.separate(
        mix: input,
        channels: 1,
        frames: input.count,
        sampleRate: 100
    )

    let modelInput = try #require(recorder.inputs.first)
    let leadingPaddingFrames = modelInput.frames - input.count
    #expect(recorder.inputs.count == 1)
    #expect(leadingPaddingFrames > 0)
    #expect(modelInput.samples.count == modelInput.frames)
    #expect(modelInput.samples.prefix(leadingPaddingFrames).allSatisfy { $0 == 0 })
    #expect(Array(modelInput.samples.suffix(input.count)) == input)
    #expect(output == input)
}

@Test("Zero shifts bypasses the shift trick")
func zeroShiftsBypassesShiftTrick() throws {
    let recorder = ModelInputRecorder()
    let input: [Float] = [0.25, -0.5, 0.75, -1]
    let engine = SeparationEngine(
        model: InputEchoModel(recorder: recorder),
        parameters: DemucsSeparationParameters(
            shifts: 0,
            overlap: 0,
            split: false,
            segmentSeconds: 1,
            batchSize: 1,
            seed: nil
        ),
        monitor: nil
    )

    let output = try engine.separate(
        mix: input,
        channels: 1,
        frames: input.count,
        sampleRate: 100
    )

    let modelInput = try #require(recorder.inputs.first)
    #expect(recorder.inputs.count == 1)
    #expect(modelInput.frames == input.count)
    #expect(modelInput.samples == input)
    #expect(output == input)
}

@Test("Chunk progress composes inside shift progress")
func chunkProgressComposesInsideShiftProgress() throws {
    let recorder = ProgressRecorder()
    let counter = PredictCallCounter()
    let model = ProgressReportingModel(
        reportedFractions: [0, 1],
        defaultSegmentSeconds: 0.01,
        callCounter: counter
    )
    let engine = SeparationEngine(
        model: model,
        parameters: DemucsSeparationParameters(
            shifts: 2,
            overlap: 0,
            split: true,
            segmentSeconds: 0.01,
            batchSize: 1,
            seed: 11
        ),
        monitor: makeMonitor(recorder: recorder)
    )

    _ = try engine.separate(mix: [0, 0, 0, 0], channels: 1, frames: 4, sampleRate: 100)

    let modelCompletions = recorder.entries
        .filter { $0.stage == "model-1.0" }
        .map(\.fraction)
    #expect(counter.count == modelCompletions.count)
    #expect(modelCompletions.count > 2)
    #expect(modelCompletions.contains { abs($0 - 0.5) < 0.000_001 })
    #expect(modelCompletions.contains { $0 > 0 && $0 < 0.5 })
    #expect(modelCompletions.contains { $0 > 0.5 && $0 < 1 })
    #expect(abs((modelCompletions.last ?? 0) - 1) < 0.000_001)
    expectMonotonicUnitProgress(recorder.entries)
}

@Test("Scoped progress shares cancellation with its parent")
func scopedProgressSharesCancellationWithParent() {
    let recorder = ProgressRecorder()
    let token = DemucsCancelToken()
    let counter = PredictCallCounter()
    let model = ProgressReportingModel(
        reportedFractions: [0.25],
        cancelDuringPrediction: true,
        callCounter: counter
    )
    let engine = SeparationEngine(
        model: model,
        parameters: DemucsSeparationParameters(
            shifts: 2,
            overlap: 0,
            split: false,
            segmentSeconds: 1,
            batchSize: 1,
            seed: 13
        ),
        monitor: makeMonitor(recorder: recorder, cancelToken: token)
    )

    do {
        _ = try engine.separate(mix: [0, 0, 0, 0], channels: 1, frames: 4, sampleRate: 100)
        Issue.record("Expected separation cancellation")
    } catch DemucsError.cancelled {
        #expect(token.isCancelled)
        #expect(counter.count == 1)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
