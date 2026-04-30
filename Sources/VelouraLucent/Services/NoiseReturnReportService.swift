import Foundation

enum NoiseReturnReportService {
    static func makeReport(
        denoiseEffect: DenoiseEffectReport?,
        corrected: AudioMetricSnapshot?,
        mastered: AudioMetricSnapshot?
    ) -> NoiseReturnReport? {
        guard let denoiseEffect, let corrected, let mastered else { return nil }

        let bands = [
            NoiseReturnBand(id: "high10to16", label: "10-16kHz高域", lowerBound: 10_000, upperBound: 16_000, denoiseDeltaDB: denoiseEffect.shimmerFlickerChangeDB),
            NoiseReturnBand(id: "hf12", label: "12kHz以上", lowerBound: 12_000, upperBound: nil, denoiseDeltaDB: denoiseEffect.hf12ChangeDB),
            NoiseReturnBand(id: "hf16", label: "16kHz以上", lowerBound: 16_000, upperBound: nil, denoiseDeltaDB: denoiseEffect.hf16ChangeDB),
            NoiseReturnBand(id: "hf18", label: "18kHz以上", lowerBound: 18_000, upperBound: nil, denoiseDeltaDB: denoiseEffect.hf18ChangeDB)
        ]

        let rows = bands.compactMap { band -> NoiseReturnRow? in
            guard
                let correctedLevel = averageLevel(in: corrected, band: band),
                let masteredLevel = averageLevel(in: mastered, band: band)
            else {
                return nil
            }

            let denoiseDelta = band.denoiseDeltaDB
            let masteringDelta = masteredLevel - correctedLevel
            let returnRate = returnRatePercent(denoiseDeltaDB: denoiseDelta, masteringDeltaDB: masteringDelta)

            return NoiseReturnRow(
                id: band.id,
                label: band.label,
                denoiseDeltaDB: denoiseDelta,
                masteringDeltaDB: masteringDelta,
                returnRatePercent: returnRate,
                severity: severity(denoiseDeltaDB: denoiseDelta, masteringDeltaDB: masteringDelta, returnRatePercent: returnRate)
            )
        }

        return rows.isEmpty ? nil : NoiseReturnReport(rows: rows)
    }

    private static func averageLevel(in metrics: AudioMetricSnapshot, band: NoiseReturnBand) -> Double? {
        let values = metrics.averageSpectrum.compactMap { point -> Double? in
            guard point.frequencyHz >= band.lowerBound else { return nil }
            if let upperBound = band.upperBound, point.frequencyHz > upperBound {
                return nil
            }
            guard point.levelDB.isFinite else { return nil }
            return point.levelDB
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func returnRatePercent(denoiseDeltaDB: Double, masteringDeltaDB: Double) -> Double? {
        guard denoiseDeltaDB < -0.05 else { return nil }
        guard masteringDeltaDB > 0.25 else { return 0 }
        return masteringDeltaDB / abs(denoiseDeltaDB) * 100
    }

    private static func severity(
        denoiseDeltaDB: Double,
        masteringDeltaDB: Double,
        returnRatePercent: Double?
    ) -> NoiseReturnSeverity {
        guard denoiseDeltaDB < -0.05, masteringDeltaDB > 0.25 else {
            return .ok
        }
        let rate = returnRatePercent ?? 0
        if rate >= 60 || masteringDeltaDB >= 2.5 {
            return .warning
        }
        if rate >= 30 || masteringDeltaDB >= 1.0 {
            return .caution
        }
        return .ok
    }
}

private struct NoiseReturnBand {
    let id: String
    let label: String
    let lowerBound: Double
    let upperBound: Double?
    let denoiseDeltaDB: Double
}
