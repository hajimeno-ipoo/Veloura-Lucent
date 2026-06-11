import Foundation

extension NativeAudioProcessor {
    func constrainCorrectionMudIncrease(
        signal: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot,
        measurementCache: NoiseMeasurementRunCache,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        var measurementCount = 0
        let currentMeasurements = measurementCache.snapshot(
            signalID: "correctionMudGuard.current",
            signal: signal,
            ids: [NoiseMeasurementID.mud]
        )
        measurementCount += 1
        guard let referenceMud = referenceMeasurements.comparableLevel(for: NoiseMeasurementID.mud),
              let currentMud = currentMeasurements.comparableLevel(for: NoiseMeasurementID.mud)
        else {
            logger?.log("低中域残り/測定回数: \(measurementCount)")
            return signal
        }

        let allowedIncreaseDB = 0.45
        let excessDB = currentMud - referenceMud - allowedIncreaseDB
        guard excessDB > 0.25 else {
            logger?.log("低中域残り/測定回数: \(measurementCount)")
            return signal
        }

        let limitMud = referenceMud + allowedIncreaseDB
        let targetGainDB = -min(max(excessDB * 1.10, 1.0), 8.0)
        let candidates = [
            targetGainDB * 0.25,
            targetGainDB * 0.50,
            targetGainDB * 0.75,
            targetGainDB,
            targetGainDB * 1.50,
            targetGainDB * 2.00,
            targetGainDB * 2.50,
            targetGainDB * 3.50,
            targetGainDB * 5.00
        ]
            .enumerated()
            .map { index, gainDB in
                let candidate = scaleCorrectionSignalBand(signal: signal, lower: 300, upper: 1_000, gainDB: gainDB)
                return (
                    score: MudCorrectionCandidateScore(
                        index: index,
                        gainDB: gainDB,
                        bandRMSDB: bandRMSDB(signal: candidate, lower: 300, upper: 1_000)
                    ),
                    signal: candidate
                )
            }
        var measuredCandidates: [(score: MudCorrectionCandidateScore, signal: AudioSignal, mud: Double)] = []
        measuredCandidates.reserveCapacity(candidates.count)
        for candidate in candidates {
            let candidateMeasurements = measurementCache.snapshot(
                signalID: "correctionMudGuard.candidate.\(candidate.score.index)",
                signal: candidate.signal,
                ids: [NoiseMeasurementID.mud]
            )
            measurementCount += 1
            let candidateMud = candidateMeasurements.comparableLevel(for: NoiseMeasurementID.mud) ?? currentMud
            measuredCandidates.append((score: candidate.score, signal: candidate.signal, mud: candidateMud))
        }
        logger?.log("低中域残り/測定回数: \(measurementCount)")

        let selectedCandidate = measuredCandidates.first { $0.mud <= limitMud }
            ?? measuredCandidates.min { lhs, rhs in
                if lhs.mud != rhs.mud { return lhs.mud < rhs.mud }
                return abs(lhs.score.gainDB) < abs(rhs.score.gainDB)
            }
        guard let selectedCandidate, selectedCandidate.mud < currentMud - 0.1 else {
            logger?.log("低中域残り: 有効なこもり改善候補がないため維持")
            return signal
        }
        logger?.log(
            "低中域残り/候補選定: \(selectedCandidate.score.index) gain \(String(format: "%.1f", selectedCandidate.score.gainDB)) dB mud \(String(format: "%.1f", selectedCandidate.mud)) dB"
        )
        if selectedCandidate.mud > limitMud {
            logger?.log("低中域残り: 基準内候補なし、最もこもりが少ない候補を採用")
        }
        logger?.log("低中域残り: こもり悪化を抑制 \(String(format: "%.1f", selectedCandidate.score.gainDB)) dB")
        return selectedCandidate.signal
    }
}
