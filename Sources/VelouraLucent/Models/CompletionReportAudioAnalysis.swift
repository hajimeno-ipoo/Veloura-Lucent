import Foundation

struct CompletionReportWaveformPoint: Sendable, Equatable {
    let time: TimeInterval
    let minimum: Float
    let maximum: Float
}

struct CompletionReportAudioAnalysis: Sendable, Equatable {
    let estimatedTempoBPM: Double?
    let tempoConfidence: Double
    let estimatedKey: String?
    let keyConfidence: Double
    let densityTransitionTimes: [TimeInterval]
    let lowBandStereoCorrelation: Double?
    let sideMidRatioDB: Double?
    let lowBandSideMidRatioDB: Double?
    let leftRightWaveformCorrelation: Double?
    let clippedSampleCount: Int
    let nearPeakSampleCount: Int
    let rms400MillisecondDB: [Double]
    let rms400MillisecondRateHz: Double
    let displayWaveform: [CompletionReportWaveformPoint]
    let waveformEnvelope: [Float]
    let waveformEnvelopeRateHz: Double

    static let unavailable = CompletionReportAudioAnalysis(
        estimatedTempoBPM: nil,
        tempoConfidence: 0,
        estimatedKey: nil,
        keyConfidence: 0,
        densityTransitionTimes: [],
        lowBandStereoCorrelation: nil,
        sideMidRatioDB: nil,
        lowBandSideMidRatioDB: nil,
        leftRightWaveformCorrelation: nil,
        clippedSampleCount: 0,
        nearPeakSampleCount: 0,
        rms400MillisecondDB: [],
        rms400MillisecondRateHz: 0,
        displayWaveform: [],
        waveformEnvelope: [],
        waveformEnvelopeRateHz: 0
    )
}
