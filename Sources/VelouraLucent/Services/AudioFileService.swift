import AVFoundation
import Accelerate
import Foundation
import UniformTypeIdentifiers

enum AudioExportFormat: String, CaseIterable, Identifiable, Sendable {
    case highQualityWAV
    case deliveryWAV
    case cdWAV
    case sharingAAC

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highQualityWAV:
            return "高品質保存"
        case .deliveryWAV:
            return "配信・納品用"
        case .cdWAV:
            return "CD用"
        case .sharingAAC:
            return "試聴共有用"
        }
    }

    var detail: String {
        switch self {
        case .highQualityWAV:
            return "32-bit float WAV / 48 kHz"
        case .deliveryWAV:
            return "24-bit PCM WAV / 48 kHz"
        case .cdWAV:
            return "16-bit PCM WAV / 44.1 kHz + TPDFディザ"
        case .sharingAAC:
            return "AAC .m4a / 48 kHz / 256 kbps"
        }
    }

    var menuTitle: String {
        "\(title)（\(detail)）"
    }

    var fileExtension: String {
        switch self {
        case .highQualityWAV, .deliveryWAV, .cdWAV:
            return "wav"
        case .sharingAAC:
            return "m4a"
        }
    }

    var contentType: UTType {
        switch self {
        case .highQualityWAV, .deliveryWAV, .cdWAV:
            return .wav
        case .sharingAAC:
            return .mpeg4Audio
        }
    }
}

enum AudioFileService {
    struct AudioDisplaySnapshots: Sendable {
        let previewSnapshot: AudioPreviewSnapshot
        let spectrogram: SpectrogramSnapshot
    }

    static let targetSampleRate = 48_000.0
    static let previewBucketCount = 384
    static let outputFileExtension = "wav"
    private static let previewFFTSize = 1024
    private static let previewHopSize = 1024
    private static let spectrogramTimeBuckets = 72
    private static let spectrogramFrequencyBuckets = 28

    static func loadAudio(from url: URL) throws -> AudioSignal {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: file.processingFormat.sampleRate, channels: file.processingFormat.channelCount, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)

        let signal = signal(from: buffer)
        if abs(signal.sampleRate - targetSampleRate) < 0.5 {
            return signal
        }
        return try convertedSampleRate(signal: signal, to: targetSampleRate)
    }

    static func saveAudio(_ signal: AudioSignal, to url: URL) throws {
        try saveAudio(signal, to: url, settings: interleavedFileSettings(sampleRate: signal.sampleRate, channels: signal.channels.count))
    }

    static func exportAudio(from sourceURL: URL, to destinationURL: URL, format: AudioExportFormat) throws {
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".veloura-export-\(UUID().uuidString)")
            .appendingPathExtension(format.fileExtension)

        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        switch format {
        case .highQualityWAV:
            try FileManager.default.copyItem(at: sourceURL, to: temporaryURL)
        case .deliveryWAV:
            let signal = try validatedEncodedSignal(from: sourceURL)
            try saveAudio(signal, to: temporaryURL, settings: pcmFileSettings(sampleRate: signal.sampleRate, channels: signal.channels.count, bitDepth: 24))
        case .cdWAV:
            let signal = try validatedEncodedSignal(from: sourceURL)
            let resampled = try convertedSampleRate(signal: signal, to: 44_100)
            let dithered = applyTPDFDither(to: resampled, bitDepth: 16)
            try saveAudio(dithered, to: temporaryURL, settings: pcmFileSettings(sampleRate: dithered.sampleRate, channels: dithered.channels.count, bitDepth: 16))
        case .sharingAAC:
            let signal = try validatedEncodedSignal(from: sourceURL)
            try saveAudio(signal, to: temporaryURL, settings: aacFileSettings(sampleRate: signal.sampleRate, channels: signal.channels.count))
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    static func applyTPDFDither(to signal: AudioSignal, bitDepth: Int, seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) -> AudioSignal {
        let leastSignificantBit = Float(1.0 / pow(2.0, Double(bitDepth - 1)))
        let maximumSample = Float(1).nextDown
        var generator = TPDFRandomNumberGenerator(state: seed)
        let channels = signal.channels.map { channel in
            channel.map { sample in
                let noise = (generator.nextUnitFloat() + generator.nextUnitFloat() - 1) * leastSignificantBit
                return min(max(sample + noise, -1), maximumSample)
            }
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private static func saveAudio(_ signal: AudioSignal, to url: URL, settings: [String: Any]) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: signal.sampleRate, channels: AVAudioChannelCount(signal.channels.count))!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(signal.frameCount))!
        buffer.frameLength = AVAudioFrameCount(signal.frameCount)
        for (channelIndex, channel) in signal.channels.enumerated() {
            guard let destination = buffer.floatChannelData?[channelIndex] else { continue }
            destination.update(from: channel, count: channel.count)
        }

        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }

    private static func validatedEncodedSignal(from url: URL) throws -> AudioSignal {
        let signal = try loadAudio(from: url)
        guard signal.channels.allSatisfy({ channel in channel.allSatisfy(\.isFinite) }) else {
            throw AppError.audioWriteFailed
        }
        let maximumSample = Float(1).nextDown
        let channels = signal.channels.map { channel in
            channel.map { min(max($0, -1), maximumSample) }
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private static func convertedSampleRate(signal sourceSignal: AudioSignal, to sampleRate: Double) throws -> AudioSignal {
        guard abs(sourceSignal.sampleRate - sampleRate) >= 0.5 else { return sourceSignal }
        let channelCount = AVAudioChannelCount(sourceSignal.channels.count)
        guard
            let inputFormat = AVAudioFormat(standardFormatWithSampleRate: sourceSignal.sampleRate, channels: channelCount),
            let outputFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount),
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else {
            throw AppError.audioWriteFailed
        }

        let inputBuffer = try pcmBuffer(from: sourceSignal, format: inputFormat)
        let outputCapacity = AVAudioFrameCount(ceil(Double(sourceSignal.frameCount) * sampleRate / sourceSignal.sampleRate)) + 64
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            throw AppError.audioWriteFailed
        }

        let inputState = AudioConverterInputState(buffer: inputBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if inputState.didProvideInput {
                inputStatus.pointee = .endOfStream
                return nil
            }
            inputState.didProvideInput = true
            inputStatus.pointee = .haveData
            return inputState.buffer
        }
        guard status != .error, conversionError == nil else {
            throw conversionError ?? AppError.audioWriteFailed
        }
        return signal(from: outputBuffer)
    }

    private static func pcmBuffer(from signal: AudioSignal, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(signal.frameCount)) else {
            throw AppError.audioWriteFailed
        }
        buffer.frameLength = AVAudioFrameCount(signal.frameCount)
        for (channelIndex, channel) in signal.channels.enumerated() {
            guard let destination = buffer.floatChannelData?[channelIndex] else {
                throw AppError.audioWriteFailed
            }
            destination.update(from: channel, count: channel.count)
        }
        return buffer
    }

    private static func signal(from buffer: AVAudioPCMBuffer) -> AudioSignal {
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        let channels = (0..<channelCount).map { channelIndex in
            Array(UnsafeBufferPointer(start: buffer.floatChannelData![channelIndex], count: frameLength))
        }
        return AudioSignal(channels: channels, sampleRate: buffer.format.sampleRate)
    }

    static func makePreviewSnapshot(for url: URL, bucketCount: Int = previewBucketCount) throws -> AudioPreviewSnapshot {
        let signal = try loadAudio(from: url)
        return makePreviewSnapshot(from: signal, bucketCount: bucketCount)
    }

    static func makePreviewSnapshot(from signal: AudioSignal, bucketCount: Int = previewBucketCount) -> AudioPreviewSnapshot {
        let mono = signal.monoMixdown()
        guard !mono.isEmpty else {
            return emptyPreviewSnapshot(bucketCount: bucketCount)
        }

        let spectralAnalysis = makePreviewSpectralAnalysis(
            mono: mono,
            sampleRate: signal.sampleRate,
            bucketCount: bucketCount,
            includesBandLevels: true,
            includesSpectrogram: false
        )
        return makePreviewSnapshot(from: signal, mono: mono, spectralAnalysis: spectralAnalysis, bucketCount: bucketCount)
    }

    static func makeDisplaySnapshots(from signal: AudioSignal, bucketCount: Int = previewBucketCount) -> AudioDisplaySnapshots {
        let mono = signal.monoMixdown()
        guard !mono.isEmpty else {
            return AudioDisplaySnapshots(
                previewSnapshot: emptyPreviewSnapshot(bucketCount: bucketCount),
                spectrogram: .empty
            )
        }

        let spectralAnalysis = makePreviewSpectralAnalysis(
            mono: mono,
            sampleRate: signal.sampleRate,
            bucketCount: bucketCount,
            includesBandLevels: true,
            includesSpectrogram: true
        )
        return AudioDisplaySnapshots(
            previewSnapshot: makePreviewSnapshot(from: signal, mono: mono, spectralAnalysis: spectralAnalysis, bucketCount: bucketCount),
            spectrogram: makeSpectrogramSnapshot(from: signal, mono: mono, spectralAnalysis: spectralAnalysis)
        )
    }

    private static func makePreviewSnapshot(from signal: AudioSignal, mono: [Float], spectralAnalysis: PreviewSpectralAnalysis, bucketCount: Int) -> AudioPreviewSnapshot {
        let chunkSize = max(1, mono.count / bucketCount)
        let waveform = stride(from: 0, to: mono.count, by: chunkSize).prefix(bucketCount).map { index in
            let end = min(index + chunkSize, mono.count)
            let slice = mono[index..<end]
            let peak = slice.map { abs($0) }.max() ?? 0
            return min(1, peak)
        }

        let (bandLevels, bandLevelDBs) = makeBandLevels(from: spectralAnalysis, bucketCount: bucketCount)

        return AudioPreviewSnapshot(
            waveform: Array(waveform),
            duration: Double(mono.count) / signal.sampleRate,
            bandLevels: bandLevels,
            bandLevelDBs: bandLevelDBs
        )
    }

    static func makeSpectrogramSnapshot(for url: URL) throws -> SpectrogramSnapshot {
        let signal = try loadAudio(from: url)
        return makeSpectrogramSnapshot(from: signal)
    }

    static func makeSpectrogramSnapshot(from signal: AudioSignal) -> SpectrogramSnapshot {
        let mono = signal.monoMixdown()
        guard !mono.isEmpty else {
            return .empty
        }

        let spectralAnalysis = makePreviewSpectralAnalysis(
            mono: mono,
            sampleRate: signal.sampleRate,
            bucketCount: previewBucketCount,
            includesBandLevels: false,
            includesSpectrogram: true
        )
        return makeSpectrogramSnapshot(from: signal, mono: mono, spectralAnalysis: spectralAnalysis)
    }

    private static func makeSpectrogramSnapshot(from signal: AudioSignal, mono: [Float], spectralAnalysis: PreviewSpectralAnalysis) -> SpectrogramSnapshot {
        guard spectralAnalysis.frameCount > 0 else {
            return .empty
        }

        let timeBuckets = spectralAnalysis.spectrogramTimeBuckets
        let frequencyBuckets = 56
        let maxFrequency = signal.sampleRate * 0.5
        let minFrequency = 80.0

        var cells: [SpectrogramCell] = []
        cells.reserveCapacity(timeBuckets * frequencyBuckets)

        var maxIntensity = -120.0
        var rawLevels = Array(repeating: Array(repeating: -120.0, count: frequencyBuckets), count: timeBuckets)

        for timeBucket in 0..<timeBuckets {
            for frequencyBucket in 0..<frequencyBuckets {
                let index = timeBucket * frequencyBuckets + frequencyBucket
                let rms = sqrt(max(Double(spectralAnalysis.spectrogramEnergy[index]) / Double(max(spectralAnalysis.spectrogramCounts[index], 1)), 1e-12))
                let levelDB = 20 * log10(max(rms, 1e-12))
                rawLevels[timeBucket][frequencyBucket] = levelDB
                maxIntensity = max(maxIntensity, levelDB)
            }
        }

        let floor = max(-96.0, maxIntensity - 58.0)
        let duration = Double(mono.count) / signal.sampleRate

        for timeBucket in 0..<timeBuckets {
            for frequencyBucket in 0..<frequencyBuckets {
                let levelDB = rawLevels[timeBucket][frequencyBucket]
                let timeStart = duration * Double(timeBucket) / Double(timeBuckets)
                let timeEnd = duration * Double(timeBucket + 1) / Double(timeBuckets)
                let lowerFrequency = minFrequency * pow(maxFrequency / minFrequency, Double(frequencyBucket) / Double(frequencyBuckets))
                let upperFrequency = minFrequency * pow(maxFrequency / minFrequency, Double(frequencyBucket + 1) / Double(frequencyBuckets))

                cells.append(
                    SpectrogramCell(
                        id: "\(timeBucket)-\(frequencyBucket)",
                        timeIndex: timeBucket,
                        bandIndex: frequencyBucket,
                        timeStart: timeStart,
                        timeEnd: timeEnd,
                        frequencyStart: lowerFrequency,
                        frequencyEnd: upperFrequency,
                        levelDB: levelDB
                    )
                )
            }
        }

        return SpectrogramSnapshot(
            cells: cells,
            timeBucketCount: timeBuckets,
            frequencyBucketCount: frequencyBuckets,
            duration: duration,
            minLevelDB: floor,
            maxLevelDB: maxIntensity
        )
    }

    private static func makeBandLevels(from mono: [Float], sampleRate: Double, bucketCount: Int) -> ([String: [Float]], [String: [Float]]) {
        let spectralAnalysis = makePreviewSpectralAnalysis(
            mono: mono,
            sampleRate: sampleRate,
            bucketCount: bucketCount,
            includesBandLevels: true,
            includesSpectrogram: false
        )
        return makeBandLevels(from: spectralAnalysis, bucketCount: bucketCount)
    }

    private static func makeBandLevels(from spectralAnalysis: PreviewSpectralAnalysis, bucketCount: Int) -> ([String: [Float]], [String: [Float]]) {
        guard spectralAnalysis.frameCount > 0 else {
            return (
                emptyBandLevels(bucketCount: bucketCount),
                emptyBandLevels(bucketCount: bucketCount, fill: -120)
            )
        }

        var bucketLevels: [String: [Float]] = Dictionary(uniqueKeysWithValues: AudioBandCatalog.previewBands.map {
            ($0.id, Array(repeating: 0, count: bucketCount))
        })
        var bucketLevelDBs: [String: [Float]] = Dictionary(uniqueKeysWithValues: AudioBandCatalog.previewBands.map {
            ($0.id, Array(repeating: Float(-120), count: bucketCount))
        })
        let framesPerBucket = max(Double(spectralAnalysis.frameCount) / Double(bucketCount), 1)

        for band in AudioBandCatalog.previewBands {
            guard let levels = spectralAnalysis.frameBandLevels[band.id] else { continue }
            let sortedLevels = levels.sorted()
            let lowerReference = percentile(sortedLevels, fraction: 0.15)
            let upperReference = percentile(sortedLevels, fraction: 0.95)
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
                bucketLevels[band.id]?[bucketIndex] = powf(normalized, 0.58)
                bucketLevelDBs[band.id]?[bucketIndex] = blendedLevel
            }
        }

        return (bucketLevels, bucketLevelDBs)
    }

    private struct PreviewSpectralAnalysis {
        let frameCount: Int
        let spectrogramTimeBuckets: Int
        let frameBandLevels: [String: [Float]]
        let spectrogramEnergy: [Float]
        let spectrogramCounts: [Int]
    }

    private static func makePreviewSpectralAnalysis(
        mono: [Float],
        sampleRate: Double,
        bucketCount _: Int,
        includesBandLevels: Bool,
        includesSpectrogram: Bool
    ) -> PreviewSpectralAnalysis {
        let frequencyStep = sampleRate / Double(previewFFTSize)
        let binCount = previewFFTSize / 2 + 1
        let previewBandRanges: [(id: String, range: ClosedRange<Int>)] = includesBandLevels
            ? AudioBandCatalog.previewBands.map { band -> (id: String, range: ClosedRange<Int>) in
                let lower = max(0, min(Int(floor(band.lowerBound / frequencyStep)), binCount - 1))
                let upper = max(lower, min(Int(floor(band.upperBound / frequencyStep)), binCount - 1))
                return (band.id, lower...upper)
            }
            : []

        let frameCount = previewSTFTFrameCount(forSampleCount: mono.count)
        let timeBuckets = min(120, max(1, frameCount))
        let frequencyBuckets = 56
        let maxFrequency = sampleRate * 0.5
        let minFrequency = 80.0
        let frameGroupSize = max(1, Int(ceil(Double(frameCount) / Double(timeBuckets))))
        let binEdges: [ClosedRange<Int>] = includesSpectrogram
            ? (0..<frequencyBuckets).map { bucket in
                let lowerRatio = Double(bucket) / Double(frequencyBuckets)
                let upperRatio = Double(bucket + 1) / Double(frequencyBuckets)
                let lowerFrequency = minFrequency * pow(maxFrequency / minFrequency, lowerRatio)
                let upperFrequency = minFrequency * pow(maxFrequency / minFrequency, upperRatio)
                let lowerBin = max(0, min(Int(lowerFrequency / frequencyStep), binCount - 1))
                let upperBin = max(lowerBin, min(Int(upperFrequency / frequencyStep), binCount - 1))
                return lowerBin...upperBin
            }
            : []

        var frames: [String: [Float]] = includesBandLevels
            ? Dictionary(uniqueKeysWithValues: previewBandRanges.map { ($0.id, Array(repeating: Float.zero, count: frameCount)) })
            : [:]
        var spectrogramEnergy = includesSpectrogram ? Array(repeating: Float.zero, count: timeBuckets * frequencyBuckets) : []
        var spectrogramCounts = includesSpectrogram ? Array(repeating: 0, count: timeBuckets * frequencyBuckets) : []

        SpectralDSP.forEachSTFTFrame(mono, fftSize: previewFFTSize, hopSize: previewHopSize) { frameIndex, _, real, imag in
            if includesBandLevels {
                for (bandID, range) in previewBandRanges {
                    var energy: Float = 0
                    for binIndex in range {
                        let value = hypotf(real[binIndex], imag[binIndex])
                        energy += value * value
                    }
                    let meanSquare = energy / Float(max(range.count, 1))
                    let rms = sqrtf(max(meanSquare, 1e-12))
                    frames[bandID]?[frameIndex] = 20 * log10f(rms)
                }
            }

            if includesSpectrogram {
                let timeBucket = min(timeBuckets - 1, frameIndex / frameGroupSize)
                for frequencyBucket in 0..<frequencyBuckets {
                    let outputIndex = timeBucket * frequencyBuckets + frequencyBucket
                    for binIndex in binEdges[frequencyBucket] {
                        let value = hypotf(real[binIndex], imag[binIndex])
                        spectrogramEnergy[outputIndex] += value * value
                        spectrogramCounts[outputIndex] += 1
                    }
                }
            }
        }

        return PreviewSpectralAnalysis(
            frameCount: frameCount,
            spectrogramTimeBuckets: timeBuckets,
            frameBandLevels: frames,
            spectrogramEnergy: spectrogramEnergy,
            spectrogramCounts: spectrogramCounts
        )
    }

    private static func previewSTFTFrameCount(forSampleCount sampleCount: Int) -> Int {
        let sourceCount = sampleCount == 0 ? 1 : sampleCount
        let paddedCount = sourceCount > 1 ? sourceCount + previewFFTSize : sourceCount
        return max(1, Int(ceil(Double(max(paddedCount - previewFFTSize, 0)) / Double(previewHopSize))) + 1)
    }

    private static func emptyPreviewSnapshot(bucketCount: Int) -> AudioPreviewSnapshot {
        AudioPreviewSnapshot(
            waveform: Array(repeating: 0, count: bucketCount),
            duration: 0,
            bandLevels: emptyBandLevels(bucketCount: bucketCount),
            bandLevelDBs: emptyBandLevels(bucketCount: bucketCount, fill: -120)
        )
    }

    private static func emptyBandLevels(bucketCount: Int, fill: Float = 0) -> [String: [Float]] {
        Dictionary(uniqueKeysWithValues: AudioBandCatalog.previewBands.map { band in
            (band.id, Array(repeating: fill, count: bucketCount))
        })
    }

    private static func percentile(_ sortedValues: [Float], fraction: Float) -> Float {
        guard !sortedValues.isEmpty else { return -120 }
        let clampedFraction = max(0, min(1, fraction))
        let position = Int(round(clampedFraction * Float(sortedValues.count - 1)))
        return sortedValues[min(max(position, 0), sortedValues.count - 1)]
    }

    static func interleavedFileSettings(sampleRate: Double, channels: Int) -> [String: Any] {
        pcmFileSettings(sampleRate: sampleRate, channels: channels, bitDepth: 32, isFloat: true)
    }

    private static func pcmFileSettings(sampleRate: Double, channels: Int, bitDepth: Int, isFloat: Bool = false) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsFloatKey: isFloat,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    private static func aacFileSettings(sampleRate: Double, channels: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 256_000
        ]
    }
}

private struct TPDFRandomNumberGenerator {
    var state: UInt64

    mutating func nextUnitFloat() -> Float {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return Float(state >> 40) / Float(1 << 24)
    }
}

private final class AudioConverterInputState: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var didProvideInput = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}
