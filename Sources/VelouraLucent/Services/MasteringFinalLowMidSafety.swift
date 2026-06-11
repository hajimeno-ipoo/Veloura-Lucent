import Foundation

extension MasteringProcessor {
    func loudnessMatchedFinalLowMidReference(reference: AudioSignal, target: AudioSignal) -> AudioSignal {
        let referenceLoudness = MasteringAnalysisService.integratedLoudness(signal: reference)
        let targetLoudness = MasteringAnalysisService.integratedLoudness(signal: target)
        guard referenceLoudness.isFinite,
              targetLoudness.isFinite,
              referenceLoudness > -69,
              targetLoudness > -69
        else {
            return reference
        }
        return MasteringSignalMath.applyGain(signal: reference, gainDB: Double(targetLoudness - referenceLoudness))
    }

    func isFinalLowMidBodyNoiseSafe(
        base: AudioSignal,
        candidate: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot?,
        originalReferenceMeasurements: NoiseMeasurementSnapshot?
    ) -> Bool {
        let checkedIDs = [NoiseMeasurementID.hum, NoiseMeasurementID.rumble]
        let baseMeasurements = NoiseMeasurementService.analyze(signal: base, ids: checkedIDs)
        let candidateMeasurements = NoiseMeasurementService.analyze(signal: candidate, ids: checkedIDs)

        for id in checkedIDs {
            guard let baseLevel = baseMeasurements.comparableLevel(for: id),
                  let candidateLevel = candidateMeasurements.comparableLevel(for: id)
            else {
                continue
            }
            if candidateLevel > baseLevel + 0.35 {
                return false
            }
            if let referenceLevel = referenceMeasurements?.comparableLevel(for: id) {
                let referenceLimit = referenceLevel + 0.75
                if baseLevel <= referenceLimit, candidateLevel > referenceLimit {
                    return false
                }
            }
            if let originalLevel = originalReferenceMeasurements?.comparableLevel(for: id) {
                let originalLimit = originalLevel + 0.75
                if baseLevel <= originalLimit, candidateLevel > originalLimit {
                    return false
                }
            }
        }
        return true
    }

}

