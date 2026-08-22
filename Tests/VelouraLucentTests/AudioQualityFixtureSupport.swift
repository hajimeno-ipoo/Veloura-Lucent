import Foundation
import Testing
@testable import VelouraLucent

enum AudioQualityFixtureError: Error {
    case missingFixtureDirectory
    case missingFixture(String)
}

func audioQualityMaxMasteringNoiseReturnDB(for id: String) -> Double {
    InternalAudioJudgementPolicy.severityLimit(for: id)?.masteringWorseningCautionDB ?? 2.0
}

func audioQualityMaxFinalHighNoiseReturnDB(for id: String) -> Double {
    max(
        audioQualityMaxMasteringNoiseReturnDB(for: id),
        InternalAudioJudgementPolicy.finalOutputMaxHighNoiseReturnDB
    )
}

func audioQualityFixtureURL(_ fileName: String) throws -> URL {
    let fileManager = FileManager.default
    var directory = URL(fileURLWithPath: fileManager.currentDirectoryPath)

    for _ in 0..<6 {
        let fixtureDirectory = directory
            .appending(path: "Tests")
            .appending(path: "Fixtures")
            .appending(path: "AudioQuality")
        let fixtureURL = fixtureDirectory.appending(path: fileName)
        if fileManager.fileExists(atPath: fixtureURL.path(percentEncoded: false)) {
            return fixtureURL
        }
        directory.deleteLastPathComponent()
    }

    throw AudioQualityFixtureError.missingFixture(fileName)
}

func audioQualityFixtureSignal(_ fileName: String) throws -> AudioSignal {
    try AudioFileService.loadAudio(from: audioQualityFixtureURL(fileName))
}

func audioQualityDiagnosticFile(in directory: URL, containing fragment: String) throws -> URL {
    let contents = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    )
    return try #require(contents.first { $0.lastPathComponent.contains(fragment) })
}

func audioQualityMasteringLoudnessBaselineMetrics(in directory: URL) throws -> AudioMetricSnapshot {
    try AudioComparisonService.analyze(fileURL: audioQualityDiagnosticFile(in: directory, containing: "06_mastering_stereo"))
}

func audioQualityBandRMSDB(signal: AudioSignal, lower: Double, upper: Double) -> Double {
    let upperBound = min(upper, signal.sampleRate * 0.5 - 100)
    guard lower < upperBound else { return -120 }
    let mono = signal.monoMixdown()
    let band = SpectralDSP.lowPass(
        SpectralDSP.highPass(mono, cutoff: lower, sampleRate: signal.sampleRate),
        cutoff: upperBound,
        sampleRate: signal.sampleRate
    )
    let meanSquare = band.reduce(0.0) { partial, sample in
        partial + Double(sample * sample)
    } / Double(max(band.count, 1))
    return 10 * log10(max(meanSquare, 1e-12))
}

func audioQualityBandDeltaDB(reference: AudioSignal, processed: AudioSignal, lower: Double, upper: Double) -> Double {
    audioQualityBandRMSDB(signal: processed, lower: lower, upper: upper)
        - audioQualityBandRMSDB(signal: reference, lower: lower, upper: upper)
}

func expectAudioQualityHighBandsNotDulled(
    reference: AudioSignal,
    processed: AudioSignal,
    maxSparkleDropDB: Double = 2.0,
    maxAirDropDB: Double = 2.0,
    maxUltraAirDropDB: Double = 2.5
) {
    #expect(audioQualityBandDeltaDB(reference: reference, processed: processed, lower: 8_000, upper: 12_000) >= -maxSparkleDropDB)
    #expect(audioQualityBandDeltaDB(reference: reference, processed: processed, lower: 12_000, upper: 16_000) >= -maxAirDropDB)
    #expect(audioQualityBandDeltaDB(reference: reference, processed: processed, lower: 16_000, upper: 20_000) >= -maxUltraAirDropDB)
}

func audioQualityMaxWindowBandRMSDB(
    signal: AudioSignal,
    lower: Double,
    upper: Double,
    windowSeconds: Double = 0.045,
    hopSeconds: Double = 0.015
) -> Double {
    let windowFrames = max(1, Int(signal.sampleRate * windowSeconds))
    let hopFrames = max(1, Int(signal.sampleRate * hopSeconds))
    guard signal.frameCount >= windowFrames else {
        return audioQualityBandRMSDB(signal: signal, lower: lower, upper: upper)
    }

    var maxValue = -120.0
    var start = 0
    while start + windowFrames <= signal.frameCount {
        let excerpt = AudioSignal(
            channels: signal.channels.map { Array($0[start..<(start + windowFrames)]) },
            sampleRate: signal.sampleRate
        )
        maxValue = max(maxValue, audioQualityBandRMSDB(signal: excerpt, lower: lower, upper: upper))
        start += hopFrames
    }
    return maxValue
}

func audioQualityExcerpt(from signal: AudioSignal, startSeconds: Double, durationSeconds: Double) throws -> AudioSignal {
    let startFrame = max(0, Int(signal.sampleRate * startSeconds))
    let frameCount = max(1, Int(signal.sampleRate * durationSeconds))
    guard startFrame < signal.frameCount else {
        throw AudioQualityFixtureError.missingFixture("excerpt start is outside the fixture")
    }
    let endFrame = min(signal.frameCount, startFrame + frameCount)
    return AudioSignal(
        channels: signal.channels.map { Array($0[startFrame..<endFrame]) },
        sampleRate: signal.sampleRate
    )
}
