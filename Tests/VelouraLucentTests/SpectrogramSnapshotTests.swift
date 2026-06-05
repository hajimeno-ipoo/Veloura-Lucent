import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

struct SpectrogramSnapshotTests {
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

    private func maxPreviewDifference(_ lhs: AudioPreviewSnapshot, _ rhs: AudioPreviewSnapshot) -> Double {
        var maxDiff = maxArrayDifference(lhs.waveform.map(Double.init), rhs.waveform.map(Double.init))
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
              lhs.cells.count == rhs.cells.count
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
                    waveform: Array(repeating: 0, count: AudioFileService.previewBucketCount),
                    duration: 0,
                    bandLevels: emptyBandLevels(bucketCount: AudioFileService.previewBucketCount),
                    bandLevelDBs: emptyBandLevels(bucketCount: AudioFileService.previewBucketCount, fill: -120)
                ),
                spectrogram: .empty
            )
        }

        let spectrogram = SpectralDSP.stft(mono, fftSize: 1024, hopSize: 1024)
        return AudioFileService.AudioDisplaySnapshots(
            previewSnapshot: referencePreviewSnapshot(signal: signal, mono: mono, spectrogram: spectrogram),
            spectrogram: referenceSpectrogramSnapshot(signal: signal, mono: mono, spectrogram: spectrogram)
        )
    }

    private func referencePreviewSnapshot(signal: AudioSignal, mono: [Float], spectrogram: Spectrogram) -> AudioPreviewSnapshot {
        let bucketCount = AudioFileService.previewBucketCount
        let chunkSize = max(1, mono.count / bucketCount)
        let waveform = stride(from: 0, to: mono.count, by: chunkSize).prefix(bucketCount).map { index in
            let end = min(index + chunkSize, mono.count)
            let peak = mono[index..<end].map { abs($0) }.max() ?? 0
            return min(1, peak)
        }
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

        var maxIntensity = -120.0
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
                maxIntensity = max(maxIntensity, levelDB)
            }
        }

        let floor = max(-96.0, maxIntensity - 58.0)
        let duration = Double(mono.count) / signal.sampleRate
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
                        levelDB: rawLevels[timeBucket][frequencyBucket]
                    )
                )
            }
        }
        return SpectrogramSnapshot(cells: cells, timeBucketCount: timeBuckets, frequencyBucketCount: frequencyBuckets, duration: duration, minLevelDB: floor, maxLevelDB: maxIntensity)
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
