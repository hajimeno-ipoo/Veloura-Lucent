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

        let allowedIncreaseDB = 0.5
        let excessDB = currentMud - referenceMud - allowedIncreaseDB
        guard excessDB > 0.25 else {
            logger?.log("低中域残り/測定回数: \(measurementCount)")
            return signal
        }

        let targetGainDB = -min(excessDB * 0.85, 3.0)
        let candidates = [targetGainDB, targetGainDB * 0.75, targetGainDB * 0.50, targetGainDB * 0.25]
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
        guard let selectedScore = MudCorrectionCandidateSelector.select(candidates.map(\.score)),
              let selectedCandidate = candidates.first(where: { $0.score.index == selectedScore.index })
        else {
            logger?.log("低中域残り/測定回数: \(measurementCount)")
            return signal
        }
        logger?.log(
            "低中域残り/候補選定: \(selectedCandidate.score.index) gain \(String(format: "%.1f", selectedCandidate.score.gainDB)) dB"
        )
        let candidateMeasurements = measurementCache.snapshot(
            signalID: "correctionMudGuard.candidate.\(selectedCandidate.score.index)",
            signal: selectedCandidate.signal,
            ids: [NoiseMeasurementID.mud]
        )
        measurementCount += 1
        let candidateMud = candidateMeasurements.comparableLevel(for: NoiseMeasurementID.mud) ?? currentMud
        logger?.log("低中域残り/測定回数: \(measurementCount)")
        if candidateMud > referenceMud + allowedIncreaseDB {
            logger?.log("低中域残り: 最終候補でもこもり基準を超過したため見送り")
            return signal
        }
        logger?.log("低中域残り: こもり悪化を抑制 \(String(format: "%.1f", selectedCandidate.score.gainDB)) dB")
        return selectedCandidate.signal
    }
}
