import Foundation

final class NoiseMeasurementRunCache {
    static let allNoiseIDs = [
        NoiseMeasurementID.hiss,
        NoiseMeasurementID.sibilance,
        NoiseMeasurementID.shimmer,
        NoiseMeasurementID.mud,
        NoiseMeasurementID.hum,
        NoiseMeasurementID.rumble,
        NoiseMeasurementID.room
    ]

    private struct Key: Hashable {
        let signalID: String
        let ids: [String]
    }

    private var storage: [Key: NoiseMeasurementSnapshot] = [:]

    func store(_ snapshot: NoiseMeasurementSnapshot, signalID: String, ids: [String]) {
        storage[Key(signalID: signalID, ids: normalized(ids))] = snapshot
    }

    func snapshot(signalID: String, signal: AudioSignal, ids: [String]) -> NoiseMeasurementSnapshot {
        let requestedIDs = normalized(ids)
        let requestedIDSet = Set(requestedIDs)
        if let cached = storage[Key(signalID: signalID, ids: requestedIDs)] {
            return cached
        }
        if let cached = storage.first(where: { key, _ in
            key.signalID == signalID && requestedIDSet.isSubset(of: Set(key.ids))
        })?.value {
            return cached
        }
        let measured = NoiseMeasurementService.analyze(signal: signal, ids: requestedIDs)
        storage[Key(signalID: signalID, ids: requestedIDs)] = measured
        return measured
    }

    private func normalized(_ ids: [String]) -> [String] {
        Array(Set(ids)).sorted()
    }
}
