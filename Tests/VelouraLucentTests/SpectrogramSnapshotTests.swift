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
}
