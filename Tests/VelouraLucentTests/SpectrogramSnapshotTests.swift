import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

struct SpectrogramSnapshotTests {
    @Test
    func waveformEnvelopePreservesSignedPeaksAndRMS() throws {
        let envelope = AudioFileService.makeWaveformEnvelope(
            from: [-1, -0.5, 0.25, 0.75],
            bucketCount: 2
        )

        #expect(envelope.count == 2)
        #expect(envelope[0].minimum == -1)
        #expect(envelope[0].maximum == -0.5)
        #expect(abs(envelope[0].rms - Float(sqrt(0.625))) < 0.0001)
        #expect(envelope[1].minimum == 0.25)
        #expect(envelope[1].maximum == 0.75)
        #expect(abs(envelope[1].rms - Float(sqrt(0.3125))) < 0.0001)
    }

    @Test
    func previewUsesHigherWaveformResolutionWithoutChangingSpectrumBuckets() throws {
        let snapshot = AudioFileService.makePreviewSnapshot(from: makeSignal())

        #expect(AudioFileService.waveformPreviewBucketCount == 16_384)
        #expect(snapshot.waveform.count == AudioFileService.waveformPreviewBucketCount)
        for band in AudioBandCatalog.previewBands {
            #expect(snapshot.bandLevels[band.id]?.count == AudioFileService.previewBucketCount)
            #expect(snapshot.bandLevelDBs[band.id]?.count == AudioFileService.previewBucketCount)
        }
    }

    @Test
    func waveformTimeTextUsesMinuteAndHourFormats() {
        #expect(waveformTimeText(0) == "0:00")
        #expect(waveformTimeText(65.9) == "1:05")
        #expect(waveformTimeText(3_661) == "1:01:01")
    }

    @Test
    func spectrogramSnapshotContainsCells() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appending(path: "spectrogram.wav")

        try makeTestTone(at: fileURL)

        let snapshot = try AudioFileService.makeSpectrogramSnapshot(for: fileURL)

        #expect(snapshot.cells.isEmpty == false)
        #expect(snapshot.timeBucketCount > 0)
        #expect(snapshot.frequencyBucketCount > 0)
        #expect(snapshot.realtimeSpectrumTimeline.count == 21)
        #expect(snapshot.realtimeSpectrumTimeline.allSatisfy { $0.count == 56 })
    }

    @Test
    func spectrogramRealtimeTimelineKeepsTenthSecondLevelChanges() throws {
        let sampleRate = 48_000.0
        let samples = (0..<Int(sampleRate)).map { index in
            let time = Double(index) / sampleRate
            let amplitude = time < 0.4 ? 0.5 : 0.01
            return Float(sin(2 * Double.pi * 1_000 * time) * amplitude)
        }
        let snapshot = AudioFileService.makeSpectrogramSnapshot(
            from: AudioSignal(channels: [samples], sampleRate: sampleRate)
        )
        #expect(snapshot.realtimeSpectrumTimeline.count > 7)
        let loudFrame = snapshot.realtimeSpectrumTimeline[2]
        let quietFrame = snapshot.realtimeSpectrumTimeline[7]
        let loudLevel = try #require(realtimeLevel(near: 1_000, in: loudFrame))
        let quietLevel = try #require(realtimeLevel(near: 1_000, in: quietFrame))

        #expect(loudLevel - quietLevel > 20)
    }

    @Test
    func spectrogramRealtimeTimelineUsesTheSameFiftySixBandAggregation() throws {
        let frequency = 1_370.0
        let snapshot = AudioFileService.makeSpectrogramSnapshot(
            from: makeToneSignal(frequency: frequency, amplitude: 0.5)
        )
        let timelineFrame = try #require(
            snapshot.realtimeSpectrumTimeline.dropFirst().first
        )
        let timelineLevel = try #require(realtimeLevel(
            near: frequency,
            in: timelineFrame
        ))
        let spectrogramLevel = try #require(maximumLevel(
            near: frequency,
            in: snapshot
        ))

        #expect(abs(timelineLevel - spectrogramLevel) < 0.1)
    }

    @Test
    func displaySnapshotsMatchSeparatePreviewAndSpectrogramSnapshots() {
        let signal = makeSignal()

        let separatePreview = AudioFileService.makePreviewSnapshot(from: signal)
        let separateSpectrogram = AudioFileService.makeSpectrogramSnapshot(from: signal)
        let displaySnapshots = AudioFileService.makeDisplaySnapshots(from: signal)

        #expect(maxPreviewDifference(separatePreview, displaySnapshots.previewSnapshot) == 0)
        #expect(maxSpectrogramDifference(separateSpectrogram, displaySnapshots.spectrogram) == 0)
    }

    @Test
    func displaySnapshotsMatchSeparateEmptySnapshots() {
        let signal = AudioSignal(channels: [[]], sampleRate: 48_000)

        let separatePreview = AudioFileService.makePreviewSnapshot(from: signal)
        let separateSpectrogram = AudioFileService.makeSpectrogramSnapshot(from: signal)
        let displaySnapshots = AudioFileService.makeDisplaySnapshots(from: signal)

        #expect(maxPreviewDifference(separatePreview, displaySnapshots.previewSnapshot) == 0)
        #expect(maxSpectrogramDifference(separateSpectrogram, displaySnapshots.spectrogram) == 0)
    }

    @Test
    func displaySnapshotsMatchReferenceSTFTAggregation() {
        let signal = makeSignal()
        let displaySnapshots = AudioFileService.makeDisplaySnapshots(from: signal)
        let referenceSnapshots = referenceDisplaySnapshots(from: signal)

        #expect(maxPreviewDifference(referenceSnapshots.previewSnapshot, displaySnapshots.previewSnapshot) == 0)
        #expect(maxSpectrogramDifference(referenceSnapshots.spectrogram, displaySnapshots.spectrogram) == 0)
    }

    @Test
    func spectrogramUsesFixedDisplayDBRange() {
        let snapshot = AudioFileService.makeSpectrogramSnapshot(from: makeSignal())

        #expect(snapshot.minLevelDB == AudioFileService.spectrogramDisplayMinimumDB)
        #expect(snapshot.maxLevelDB == AudioFileService.spectrogramDisplayMaximumDB)
        #expect(snapshot.cells.allSatisfy {
            $0.levelDB >= AudioFileService.spectrogramDisplayMinimumDB
                && $0.levelDB <= AudioFileService.spectrogramDisplayMaximumDB
        })
    }

    @Test
    func spectrogramPreservesTwentyDBAmplitudeDifferenceAcrossFrequencyBuckets() throws {
        for frequency in [100.0, 250.0, 1_000.0, 4_000.0, 10_000.0, 18_000.0] {
            let louder = AudioFileService.makeSpectrogramSnapshot(
                from: makeToneSignal(frequency: frequency, amplitude: 0.5)
            )
            let quieter = AudioFileService.makeSpectrogramSnapshot(
                from: makeToneSignal(frequency: frequency, amplitude: 0.05)
            )
            let louderLevel = try #require(maximumLevel(near: frequency, in: louder))
            let quieterLevel = try #require(maximumLevel(near: frequency, in: quieter))

            #expect(abs((quieterLevel - louderLevel) + 20) < 0.1)
        }
    }

    @Test
    func spectrogramKeepsOppositePhaseStereoEnergy() throws {
        let mono = makeToneSignal(frequency: 1_000, amplitude: 0.5)
        let left = try #require(mono.channels.first)
        let inPhase = AudioSignal(channels: [left, left], sampleRate: mono.sampleRate)
        let oppositePhase = AudioSignal(channels: [left, left.map { -$0 }], sampleRate: mono.sampleRate)

        let inPhaseSnapshot = AudioFileService.makeSpectrogramSnapshot(from: inPhase)
        let oppositePhaseSnapshot = AudioFileService.makeSpectrogramSnapshot(from: oppositePhase)
        let inPhaseLevel = try #require(maximumLevel(near: 1_000, in: inPhaseSnapshot))
        let oppositePhaseLevel = try #require(maximumLevel(near: 1_000, in: oppositePhaseSnapshot))
        let inPhaseRealtimeLevel = try #require(realtimeLevel(
            near: 1_000,
            in: inPhaseSnapshot.realtimeSpectrumTimeline[5]
        ))
        let oppositePhaseRealtimeLevel = try #require(realtimeLevel(
            near: 1_000,
            in: oppositePhaseSnapshot.realtimeSpectrumTimeline[5]
        ))

        #expect(abs(inPhaseLevel - oppositePhaseLevel) < 0.000_001)
        #expect(oppositePhaseLevel > AudioFileService.spectrogramDisplayMinimumDB)
        #expect(abs(inPhaseRealtimeLevel - oppositePhaseRealtimeLevel) < 0.000_001)
        #expect(oppositePhaseRealtimeLevel > AudioFileService.spectrogramDisplayMinimumDB)
    }

    @Test
    func equalAmplitudeTonesRemainComparableAcrossFrequencyBuckets() throws {
        let levels = try [100.0, 250.0, 1_000.0, 4_000.0, 10_000.0, 18_000.0].map { frequency in
            let snapshot = AudioFileService.makeSpectrogramSnapshot(
                from: makeToneSignal(frequency: frequency, amplitude: 0.5)
            )
            return try #require(maximumLevel(near: frequency, in: snapshot))
        }

        let maximum = try #require(levels.max())
        let minimum = try #require(levels.min())

        #expect(maximum - minimum < 3.2)
    }

    @Test
    func displayColorScaleUsesFixedEndpoints() {
        #expect(SpectrogramDisplayColorScale.normalizedPosition(for: -120) == 0)
        #expect(SpectrogramDisplayColorScale.normalizedPosition(for: -100) == 0)
        #expect(SpectrogramDisplayColorScale.normalizedPosition(for: -50) == 0.5)
        #expect(SpectrogramDisplayColorScale.normalizedPosition(for: 0) == 1)
        #expect(SpectrogramDisplayColorScale.normalizedPosition(for: 12) == 1)
    }

    private func makeTestTone(at url: URL) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 2)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            let t = Double(index) / sampleRate
            channel[index] = Float(sin(2 * Double.pi * 440 * t) * 0.1 + sin(2 * Double.pi * 4000 * t) * 0.03)
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1)
        )
        try file.write(from: buffer)
    }

    private func makeSignal() -> AudioSignal {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 2)
        let samples = (0..<frameCount).map { index in
            let t = Double(index) / sampleRate
            return Float(sin(2 * Double.pi * 440 * t) * 0.1 + sin(2 * Double.pi * 4000 * t) * 0.03)
        }
        return AudioSignal(channels: [samples], sampleRate: sampleRate)
    }

    private func makeToneSignal(frequency: Double, amplitude: Double) -> AudioSignal {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate)
        let samples = (0..<frameCount).map { index in
            let time = Double(index) / sampleRate
            return Float(sin(2 * Double.pi * frequency * time) * amplitude)
        }
        return AudioSignal(channels: [samples], sampleRate: sampleRate)
    }

    private func maximumLevel(near frequency: Double, in snapshot: SpectrogramSnapshot) -> Double? {
        snapshot.cells
            .filter { $0.frequencyStart <= frequency && frequency <= $0.frequencyEnd }
            .map(\.levelDB)
            .max()
    }

    private func realtimeLevel(
        near frequency: Double,
        in frame: [RealtimeSpectrumPoint]
    ) -> Double? {
        frame.min {
            abs($0.frequencyHz - frequency) < abs($1.frequencyHz - frequency)
        }?.levelDB
    }

    private func maxPreviewDifference(_ lhs: AudioPreviewSnapshot, _ rhs: AudioPreviewSnapshot) -> Double {
        guard lhs.waveform.count == rhs.waveform.count else {
            return .infinity
        }

        var maxDiff = 0.0
        for (left, right) in zip(lhs.waveform, rhs.waveform) {
            maxDiff = max(maxDiff, abs(Double(left.minimum - right.minimum)))
            maxDiff = max(maxDiff, abs(Double(left.maximum - right.maximum)))
            maxDiff = max(maxDiff, abs(Double(left.rms - right.rms)))
        }
        maxDiff = max(maxDiff, abs(lhs.duration - rhs.duration))
        for band in AudioBandCatalog.previewBands {
            maxDiff = max(maxDiff, maxArrayDifference((lhs.bandLevels[band.id] ?? []).map(Double.init), (rhs.bandLevels[band.id] ?? []).map(Double.init)))
            maxDiff = max(maxDiff, maxArrayDifference((lhs.bandLevelDBs[band.id] ?? []).map(Double.init), (rhs.bandLevelDBs[band.id] ?? []).map(Double.init)))
        }
        return maxDiff
    }

    private func maxSpectrogramDifference(_ lhs: SpectrogramSnapshot, _ rhs: SpectrogramSnapshot) -> Double {
        guard lhs.timeBucketCount == rhs.timeBucketCount,
              lhs.frequencyBucketCount == rhs.frequencyBucketCount,
              lhs.cells.count == rhs.cells.count,
              lhs.realtimeSpectrumTimeline.count == rhs.realtimeSpectrumTimeline.count
        else {
            return .infinity
        }

        var maxDiff = max(
            abs(lhs.duration - rhs.duration),
            max(abs(lhs.minLevelDB - rhs.minLevelDB), abs(lhs.maxLevelDB - rhs.maxLevelDB))
        )
        for (left, right) in zip(lhs.cells, rhs.cells) {
            guard left.id == right.id,
                  left.timeIndex == right.timeIndex,
                  left.bandIndex == right.bandIndex
            else {
                return .infinity
            }
            maxDiff = max(maxDiff, abs(left.timeStart - right.timeStart))
            maxDiff = max(maxDiff, abs(left.timeEnd - right.timeEnd))
            maxDiff = max(maxDiff, abs(left.frequencyStart - right.frequencyStart))
            maxDiff = max(maxDiff, abs(left.frequencyEnd - right.frequencyEnd))
            maxDiff = max(maxDiff, abs(left.levelDB - right.levelDB))
        }
        for (leftFrame, rightFrame) in zip(
            lhs.realtimeSpectrumTimeline,
            rhs.realtimeSpectrumTimeline
        ) {
            guard leftFrame.count == rightFrame.count else {
                return .infinity
            }
            for (left, right) in zip(leftFrame, rightFrame) {
                guard left.id == right.id else {
                    return .infinity
                }
                maxDiff = max(maxDiff, abs(left.frequencyHz - right.frequencyHz))
                maxDiff = max(maxDiff, abs(left.levelDB - right.levelDB))
            }
        }
        return maxDiff
    }

    private func maxArrayDifference(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count else {
            return .infinity
        }
        return zip(lhs, rhs).map { abs($0 - $1) }.max() ?? 0
    }

    private func referenceDisplaySnapshots(from signal: AudioSignal) -> AudioFileService.AudioDisplaySnapshots {
        let mono = signal.monoMixdown()
        guard !mono.isEmpty else {
            return AudioFileService.AudioDisplaySnapshots(
                previewSnapshot: AudioPreviewSnapshot(
                    waveform: Array(repeating: .zero, count: AudioFileService.waveformPreviewBucketCount),
                    duration: 0,
                    bandLevels: emptyBandLevels(bucketCount: AudioFileService.previewBucketCount),
                    bandLevelDBs: emptyBandLevels(bucketCount: AudioFileService.previewBucketCount, fill: -120)
                ),
                spectrogram: .empty
            )
        }

        let spectrogram = SpectralDSP.stft(mono, fftSize: 1024, hopSize: 512)
        return AudioFileService.AudioDisplaySnapshots(
            previewSnapshot: referencePreviewSnapshot(signal: signal, mono: mono, spectrogram: spectrogram),
            spectrogram: referenceSpectrogramSnapshot(signal: signal, mono: mono, spectrogram: spectrogram)
        )
    }

    private func referencePreviewSnapshot(signal: AudioSignal, mono: [Float], spectrogram: Spectrogram) -> AudioPreviewSnapshot {
        let bucketCount = AudioFileService.previewBucketCount
        let waveform = AudioFileService.makeWaveformEnvelope(
            from: mono,
            bucketCount: AudioFileService.waveformPreviewBucketCount
        )
        let (bandLevels, bandLevelDBs) = referenceBandLevels(from: spectrogram, sampleRate: signal.sampleRate, bucketCount: bucketCount)

        return AudioPreviewSnapshot(
            waveform: Array(waveform),
            duration: Double(mono.count) / signal.sampleRate,
            bandLevels: bandLevels,
            bandLevelDBs: bandLevelDBs
        )
    }

    private func referenceSpectrogramSnapshot(signal: AudioSignal, mono: [Float], spectrogram: Spectrogram) -> SpectrogramSnapshot {
        guard spectrogram.frameCount > 0 else { return .empty }

        let timeBuckets = min(120, max(1, spectrogram.frameCount))
        let frequencyBuckets = 56
        let maxFrequency = signal.sampleRate * 0.5
        let minFrequency = 80.0
        let frameGroupSize = max(1, Int(ceil(Double(spectrogram.frameCount) / Double(timeBuckets))))
        let frequencyStep = signal.sampleRate / Double(spectrogram.fftSize)
        let binEdges: [ClosedRange<Int>] = (0..<frequencyBuckets).map { bucket in
            let lowerRatio = Double(bucket) / Double(frequencyBuckets)
            let upperRatio = Double(bucket + 1) / Double(frequencyBuckets)
            let lowerFrequency = minFrequency * pow(maxFrequency / minFrequency, lowerRatio)
            let upperFrequency = minFrequency * pow(maxFrequency / minFrequency, upperRatio)
            let lowerBin = max(0, min(Int(lowerFrequency / frequencyStep), spectrogram.binCount - 1))
            let upperBin = max(lowerBin, min(Int(upperFrequency / frequencyStep), spectrogram.binCount - 1))
            return lowerBin...upperBin
        }
        let duration = Double(mono.count) / signal.sampleRate
        let realtimeInterval = RealtimeSpectrumAnalyzer.timelineInterval
        let realtimeTimeBuckets = max(1, Int(ceil(duration / realtimeInterval)) + 1)

        var rawLevels = Array(repeating: Array(repeating: -120.0, count: frequencyBuckets), count: timeBuckets)
        for timeBucket in 0..<timeBuckets {
            let startFrame = timeBucket * frameGroupSize
            let endFrame = min(spectrogram.frameCount, startFrame + frameGroupSize)
            guard startFrame < endFrame else { continue }
            for frequencyBucket in 0..<frequencyBuckets {
                var energy: Float = 0
                var count = 0
                for frameIndex in startFrame..<endFrame {
                    for binIndex in binEdges[frequencyBucket] {
                        let value = spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
                        energy += value * value
                        count += 1
                    }
                }
                let rms = sqrt(max(Double(energy) / Double(max(count, 1)), 1e-12))
                let levelDB = 20 * log10(max(rms, 1e-12))
                rawLevels[timeBucket][frequencyBucket] = levelDB
            }
        }

        var realtimeLevels = Array(
            repeating: Double(-120),
            count: realtimeTimeBuckets * frequencyBuckets
        )
        var nextRealtimeTimeBucket = 0
        var previousRealtimeFrameTime: Double?
        var previousRealtimeFrameLevels: [Double]?
        for frameIndex in 0..<spectrogram.frameCount {
            let frameTime = min(
                Double(frameIndex * spectrogram.hopSize) / signal.sampleRate,
                duration
            )
            var frameLevels = Array(repeating: Double(-120), count: frequencyBuckets)
            for frequencyBucket in 0..<frequencyBuckets {
                var frameEnergy: Float = 0
                for binIndex in binEdges[frequencyBucket] {
                    let value = spectrogram.magnitude(
                        frameIndex: frameIndex,
                        binIndex: binIndex
                    )
                    frameEnergy += value * value
                }
                let rms = sqrt(max(
                    Double(frameEnergy) / Double(max(binEdges[frequencyBucket].count, 1)),
                    1e-12
                ))
                frameLevels[frequencyBucket] = AudioFileService.spectrogramDisplayLevelDB(
                    rawLevelDB: 20 * log10(max(rms, 1e-12)),
                    binCount: binEdges[frequencyBucket].count
                )
            }
            while nextRealtimeTimeBucket < realtimeTimeBuckets {
                let targetTime = Double(nextRealtimeTimeBucket) * realtimeInterval
                guard targetTime <= frameTime else { break }
                let nearestFrameLevels: [Double]
                if let previousRealtimeFrameTime,
                   let previousRealtimeFrameLevels,
                   targetTime - previousRealtimeFrameTime <= frameTime - targetTime
                {
                    nearestFrameLevels = previousRealtimeFrameLevels
                } else {
                    nearestFrameLevels = frameLevels
                }
                let destination = nextRealtimeTimeBucket * frequencyBuckets
                realtimeLevels.replaceSubrange(
                    destination..<(destination + frequencyBuckets),
                    with: nearestFrameLevels
                )
                nextRealtimeTimeBucket += 1
            }
            previousRealtimeFrameTime = frameTime
            previousRealtimeFrameLevels = frameLevels
        }
        if let previousRealtimeFrameLevels {
            while nextRealtimeTimeBucket < realtimeTimeBuckets {
                let destination = nextRealtimeTimeBucket * frequencyBuckets
                realtimeLevels.replaceSubrange(
                    destination..<(destination + frequencyBuckets),
                    with: previousRealtimeFrameLevels
                )
                nextRealtimeTimeBucket += 1
            }
        }
        let realtimeSpectrumTimeline = (0..<realtimeTimeBuckets).map { timeBucket in
            (0..<frequencyBuckets).map { frequencyBucket in
                let lowerFrequency = minFrequency * pow(
                    maxFrequency / minFrequency,
                    Double(frequencyBucket) / Double(frequencyBuckets)
                )
                let upperFrequency = minFrequency * pow(
                    maxFrequency / minFrequency,
                    Double(frequencyBucket + 1) / Double(frequencyBuckets)
                )
                let index = timeBucket * frequencyBuckets + frequencyBucket
                return RealtimeSpectrumPoint(
                    id: "comparison-\(frequencyBucket)",
                    frequencyHz: sqrt(lowerFrequency * upperFrequency),
                    levelDB: realtimeLevels[index]
                )
            }
        }
        var cells: [SpectrogramCell] = []
        cells.reserveCapacity(timeBuckets * frequencyBuckets)
        for timeBucket in 0..<timeBuckets {
            for frequencyBucket in 0..<frequencyBuckets {
                cells.append(
                    SpectrogramCell(
                        id: "\(timeBucket)-\(frequencyBucket)",
                        timeIndex: timeBucket,
                        bandIndex: frequencyBucket,
                        timeStart: duration * Double(timeBucket) / Double(timeBuckets),
                        timeEnd: duration * Double(timeBucket + 1) / Double(timeBuckets),
                        frequencyStart: minFrequency * pow(maxFrequency / minFrequency, Double(frequencyBucket) / Double(frequencyBuckets)),
                        frequencyEnd: minFrequency * pow(maxFrequency / minFrequency, Double(frequencyBucket + 1) / Double(frequencyBuckets)),
                        levelDB: AudioFileService.spectrogramDisplayLevelDB(
                            rawLevelDB: rawLevels[timeBucket][frequencyBucket],
                            binCount: binEdges[frequencyBucket].count
                        )
                    )
                )
            }
        }
        return SpectrogramSnapshot(
            cells: cells,
            timeBucketCount: timeBuckets,
            frequencyBucketCount: frequencyBuckets,
            duration: duration,
            minLevelDB: AudioFileService.spectrogramDisplayMinimumDB,
            maxLevelDB: AudioFileService.spectrogramDisplayMaximumDB,
            realtimeSpectrumTimeline: realtimeSpectrumTimeline
        )
    }

    private func referenceBandLevels(from spectrogram: Spectrogram, sampleRate: Double, bucketCount: Int) -> ([String: [Float]], [String: [Float]]) {
        guard spectrogram.frameCount > 0 else {
            return (emptyBandLevels(bucketCount: bucketCount), emptyBandLevels(bucketCount: bucketCount, fill: -120))
        }

        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let bandBinRanges = AudioBandCatalog.previewBands.map { band -> (String, ClosedRange<Int>) in
            let lower = max(0, min(Int(floor(band.lowerBound / frequencyStep)), spectrogram.binCount - 1))
            let upper = max(lower, min(Int(floor(band.upperBound / frequencyStep)), spectrogram.binCount - 1))
            return (band.id, lower...upper)
        }
        var frameBandLevels = Dictionary(uniqueKeysWithValues: bandBinRanges.map { ($0.0, Array(repeating: Float.zero, count: spectrogram.frameCount)) })
        var frameMagnitudes = Array(repeating: Float.zero, count: spectrogram.binCount)
        for frameIndex in 0..<spectrogram.frameCount {
            spectrogram.fillMagnitudes(frameIndex: frameIndex, into: &frameMagnitudes)
            for (bandID, range) in bandBinRanges {
                var energy: Float = 0
                for binIndex in range {
                    let value = frameMagnitudes[binIndex]
                    energy += value * value
                }
                let meanSquare = energy / Float(max(range.count, 1))
                let rms = sqrtf(max(meanSquare, 1e-12))
                frameBandLevels[bandID]?[frameIndex] = 20 * log10f(rms)
            }
        }

        var bucketLevels = Dictionary(uniqueKeysWithValues: bandBinRanges.map { ($0.0, Array(repeating: Float.zero, count: bucketCount)) })
        var bucketLevelDBs = Dictionary(uniqueKeysWithValues: bandBinRanges.map { ($0.0, Array(repeating: Float(-120), count: bucketCount)) })
        let framesPerBucket = max(Double(spectrogram.frameCount) / Double(bucketCount), 1)
        for (bandID, levels) in frameBandLevels {
            let sortedLevels = levels.sorted()
            let lowerReference = referencePercentile(sortedLevels, fraction: 0.15)
            let upperReference = referencePercentile(sortedLevels, fraction: 0.95)
            let spanFloor = upperReference - 24
            let floorLevel = min(lowerReference, spanFloor)
            let ceilingLevel = max(upperReference, floorLevel + 6)
            for bucketIndex in 0..<bucketCount {
                let start = Int(floor(Double(bucketIndex) * framesPerBucket))
                let end = min(levels.count, Int(ceil(Double(bucketIndex + 1) * framesPerBucket)))
                guard start < end else { continue }
                let bucketSlice = levels[start..<end]
                let bucketMean = bucketSlice.reduce(0, +) / Float(bucketSlice.count)
                let bucketPeak = bucketSlice.max() ?? bucketMean
                let blendedLevel = bucketMean + (bucketPeak - bucketMean) * 0.45
                let normalized = max(0, min(1, (blendedLevel - floorLevel) / max(ceilingLevel - floorLevel, 1)))
                bucketLevels[bandID]?[bucketIndex] = powf(normalized, 0.58)
                bucketLevelDBs[bandID]?[bucketIndex] = blendedLevel
            }
        }
        return (bucketLevels, bucketLevelDBs)
    }

    private func emptyBandLevels(bucketCount: Int, fill: Float = 0) -> [String: [Float]] {
        Dictionary(uniqueKeysWithValues: AudioBandCatalog.previewBands.map { ($0.id, Array(repeating: fill, count: bucketCount)) })
    }

    private func referencePercentile(_ sortedValues: [Float], fraction: Float) -> Float {
        guard !sortedValues.isEmpty else { return -120 }
        let clampedFraction = max(0, min(1, fraction))
        let position = Int(round(clampedFraction * Float(sortedValues.count - 1)))
        return sortedValues[min(max(position, 0), sortedValues.count - 1)]
    }
}
