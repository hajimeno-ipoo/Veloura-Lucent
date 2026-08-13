import Foundation

enum StemValidationPhase: String, Equatable, Sendable {
    case separatedStems
    case remix
    case correctedPureSum
    case processedRemix
}

enum StemValidationCheck: String, CaseIterable, Equatable, Sendable {
    case stemCount
    case roleCoverage
    case channelFrameCounts
    case sampleRate
    case channelCount
    case finiteSamples
    case finiteMeasurements
    case audioComparison
    case bandEnergies
    case noiseMeasurements
    case residual
    case peak
    case correlation
}

/// Canonical入力とraw再ミックスを、通常モードと同じnoise測定型で比較するための値です。
/// Stem単体の測定値や、存在しない補正前後の値は、この契約に含まれません。
struct StemRemixNoiseValidationContext: Sendable, Equatable {
    let canonicalInput: NoiseMeasurementSnapshot
    let rawRemix: NoiseMeasurementSnapshot
}

/// canonical入力、raw純粋加算、補正済み純粋加算の測定結果を相互比較する値です。
/// 音楽的な採用可否や候補選択は、この解析・構造検証契約に含めません。
struct StemCorrectedRemixNoiseValidationContext: Sendable, Equatable {
    let canonicalInput: NoiseMeasurementSnapshot
    let rawRemix: NoiseMeasurementSnapshot
    let correctedPureSum: NoiseMeasurementSnapshot
}

struct StemValidationFailure: Equatable, Sendable {
    let check: StemValidationCheck
    let subject: String
    let detail: String
}

struct StemValidationMeasurement: Equatable, Sendable, Identifiable {
    let id: String
    let value: Double
    let unit: String
}

struct StemValidationResult: Equatable, Sendable {
    let phase: StemValidationPhase
    let failedChecks: [StemValidationFailure]
    let measurements: [StemValidationMeasurement]

    var passed: Bool {
        failedChecks.isEmpty
    }

    /// 音声処理を継続できる構造かを示します。
    /// 帯域・ノイズ・残差・相関などの解析上の問題は記録しますが、
    /// それだけを理由に安全な音声処理を停止しません。
    var canContinue: Bool {
        failedChecks.allSatisfy { !Self.continuationBlockingChecks.contains($0.check) }
    }

    var analysisIssues: [StemValidationFailure] {
        failedChecks.filter { !Self.continuationBlockingChecks.contains($0.check) }
    }

    var failedCheckKinds: Set<StemValidationCheck> {
        Set(failedChecks.map(\.check))
    }

    func measurement(id: String) -> StemValidationMeasurement? {
        measurements.first { $0.id == id }
    }

    private static let continuationBlockingChecks: Set<StemValidationCheck> = [
        .stemCount,
        .roleCoverage,
        .channelFrameCounts,
        .sampleRate,
        .channelCount,
        .finiteSamples,
        .finiteMeasurements
    ]
}

struct StemValidationService: Sendable {
    private static let defaultValidationRoles: [StemRole] = [.drums, .bass, .other, .vocals]
    private static let defaultPureSumOrder: [StemRole] = [.vocals, .drums, .bass, .other]
    private static let comparisonBandIDs = AudioBandCatalog.comparisonBands.map(\.id)
    private static let noiseMeasurementIDs = [
        NoiseMeasurementID.hiss,
        NoiseMeasurementID.sibilance,
        NoiseMeasurementID.shimmer,
        NoiseMeasurementID.mud,
        NoiseMeasurementID.hum,
        NoiseMeasurementID.rumble,
        NoiseMeasurementID.room
    ]

    private let comparisonBandAnalyzer: @Sendable (AudioSignal) throws -> [BandEnergyMetric]

    init(
        comparisonBandAnalyzer: @escaping @Sendable (AudioSignal) throws -> [BandEnergyMetric] = {
            try AudioComparisonService.analyze(signal: $0).bandEnergies
        }
    ) {
        self.comparisonBandAnalyzer = comparisonBandAnalyzer
    }

    func validateSeparatedStems(
        source: AudioSignal,
        stems: [StemMixInput],
        validationRoles: [StemRole] = Self.defaultValidationRoles,
        pureSumOrder: [StemRole] = Self.defaultPureSumOrder,
        expectedSampleRate: Double,
        expectedChannelCount: Int
    ) -> StemValidationResult {
        var failures: [StemValidationFailure] = []
        var measurements: [StemValidationMeasurement] = []

        failures.append(contentsOf: validateExpectedStereoContract(expectedChannelCount))
        failures.append(contentsOf: validateExpectedSampleRateContract(expectedSampleRate))

        let expectedRoleSet = Set(validationRoles)
        if validationRoles.isEmpty
            || expectedRoleSet.count != validationRoles.count
            || Set(pureSumOrder).count != pureSumOrder.count
            || expectedRoleSet != Set(pureSumOrder) {
            failures.append(
                StemValidationFailure(
                    check: .roleCoverage,
                    subject: "validation-contract",
                    detail: "検証役割と純粋加算順が一致しません"
                )
            )
        }

        if stems.count != validationRoles.count {
            failures.append(
                StemValidationFailure(
                    check: .stemCount,
                    subject: "stems",
                    detail: "期待: \(validationRoles.count)、実際: \(stems.count)"
                )
            )
        }

        var signals: [StemRole: AudioSignal] = [:]
        for stem in stems {
            if signals.updateValue(stem.signal, forKey: stem.role) != nil {
                failures.append(
                    StemValidationFailure(
                        check: .roleCoverage,
                        subject: stem.role.rawValue,
                        detail: "役割が重複しています"
                    )
                )
            }
        }
        for role in signals.keys where !expectedRoleSet.contains(role) {
            failures.append(
                StemValidationFailure(
                    check: .roleCoverage,
                    subject: role.rawValue,
                    detail: "契約外の役割です"
                )
            )
        }
        for role in validationRoles where signals[role] == nil {
            failures.append(
                StemValidationFailure(
                    check: .roleCoverage,
                    subject: role.rawValue,
                    detail: "役割がありません"
                )
            )
        }

        failures.append(
            contentsOf: validateSignal(
                source,
                subject: "source",
                expectedSampleRate: expectedSampleRate,
                expectedChannelCount: expectedChannelCount,
                expectedFrameCount: nil
            )
        )
        let expectedFrameCount = source.frameCount
        for role in validationRoles {
            guard let signal = signals[role] else { continue }
            failures.append(
                contentsOf: validateSignal(
                    signal,
                    subject: role.rawValue,
                    expectedSampleRate: expectedSampleRate,
                    expectedChannelCount: expectedChannelCount,
                    expectedFrameCount: expectedFrameCount
                )
            )
        }

        guard failures.isEmpty,
              let summed = sumSignals(signals, order: pureSumOrder)
        else {
            return StemValidationResult(
                phase: .separatedStems,
                failedChecks: failures,
                measurements: measurements
            )
        }

        if containsNonFiniteSample(summed) {
            failures.append(
                StemValidationFailure(
                    check: .finiteSamples,
                    subject: "raw-stem-sum",
                    detail: "Float32純粋加算でNaNまたはInfinityが生じました"
                )
            )
            return StemValidationResult(
                phase: .separatedStems,
                failedChecks: failures,
                measurements: measurements
            )
        }

        measurements.append(contentsOf: peakMeasurements(signal: source, prefix: "source"))
        for role in validationRoles {
            if let signal = signals[role] {
                measurements.append(
                    contentsOf: peakMeasurements(signal: signal, prefix: "stem.\(role.rawValue)")
                )
            }
        }
        measurements.append(contentsOf: peakMeasurements(signal: summed, prefix: "raw-stem-sum"))
        measurements.append(contentsOf: residualMeasurements(source: source, sum: summed))
        measurements.append(contentsOf: correlationMeasurements(reference: source, candidate: summed))
        if let stereoCorrelation = normalizedCorrelation(
            summed.channels[0],
            summed.channels[1]
        ) {
            measurements.append(
                StemValidationMeasurement(
                    id: "raw-stem-sum.stereo-correlation",
                    value: stereoCorrelation,
                    unit: "ratio"
                )
            )
        }

        return finalizedResult(
            phase: .separatedStems,
            failedChecks: failures,
            measurements: measurements
        )
    }

    func validateRemix(
        reference: AudioSignal,
        remix: AudioSignal,
        noiseContext: StemRemixNoiseValidationContext,
        expectedSampleRate: Double,
        expectedChannelCount: Int
    ) -> StemValidationResult {
        var failures = validateExpectedStereoContract(expectedChannelCount)
        failures.append(contentsOf: validateExpectedSampleRateContract(expectedSampleRate))
        failures.append(contentsOf: validateSignal(
            reference,
            subject: "reference",
            expectedSampleRate: expectedSampleRate,
            expectedChannelCount: expectedChannelCount,
            expectedFrameCount: nil
        ))
        failures.append(
            contentsOf: validateSignal(
                remix,
                subject: "raw-remix",
                expectedSampleRate: expectedSampleRate,
                expectedChannelCount: expectedChannelCount,
                expectedFrameCount: reference.frameCount
            )
        )

        guard failures.isEmpty else {
            return StemValidationResult(
                phase: .remix,
                failedChecks: failures,
                measurements: []
            )
        }

        var measurements = peakMeasurements(signal: remix, prefix: "raw-remix")
        measurements.append(contentsOf: residualMeasurements(source: reference, sum: remix, prefix: "remix-difference"))
        measurements.append(contentsOf: correlationMeasurements(reference: reference, candidate: remix))
        if let stereoCorrelation = normalizedCorrelation(remix.channels[0], remix.channels[1]) {
            measurements.append(
                StemValidationMeasurement(
                    id: "raw-remix.stereo-correlation",
                    value: stereoCorrelation,
                    unit: "ratio"
                )
            )
        }
        let bandValidation = validateComparisonBands(reference: reference, remix: remix)
        failures.append(contentsOf: bandValidation.failures)
        measurements.append(contentsOf: bandValidation.measurements)

        let noiseValidation = validateRemixNoise(context: noiseContext)
        failures.append(contentsOf: noiseValidation.failures)
        measurements.append(contentsOf: noiseValidation.measurements)

        return finalizedResult(
            phase: .remix,
            failedChecks: failures,
            measurements: measurements
        )
    }

    /// Validates that all three 44.1 kHz remix comparison signals are structurally
    /// measurable, then records their pairwise changes. This result deliberately makes
    /// no musical selection decision between the raw and corrected remixes.
    func validateCorrectedRemix(
        canonicalReference: AudioSignal,
        rawRemix: AudioSignal,
        correctedRemix: AudioSignal,
        noiseContext: StemCorrectedRemixNoiseValidationContext,
        expectedSampleRate: Double,
        expectedChannelCount: Int
    ) -> StemValidationResult {
        var failures = validateExpectedStereoContract(expectedChannelCount)
        failures.append(contentsOf: validateExpectedSampleRateContract(expectedSampleRate))
        failures.append(contentsOf: validateSignal(
            canonicalReference,
            subject: "canonical-input",
            expectedSampleRate: expectedSampleRate,
            expectedChannelCount: expectedChannelCount,
            expectedFrameCount: nil
        ))
        failures.append(contentsOf: validateSignal(
            rawRemix,
            subject: "raw-remix",
            expectedSampleRate: expectedSampleRate,
            expectedChannelCount: expectedChannelCount,
            expectedFrameCount: canonicalReference.frameCount
        ))
        failures.append(contentsOf: validateSignal(
            correctedRemix,
            subject: "corrected-remix",
            expectedSampleRate: expectedSampleRate,
            expectedChannelCount: expectedChannelCount,
            expectedFrameCount: canonicalReference.frameCount
        ))

        guard failures.isEmpty else {
            return StemValidationResult(
                phase: .correctedPureSum,
                failedChecks: failures,
                measurements: []
            )
        }

        var measurements = peakMeasurements(
            signal: correctedRemix,
            prefix: "corrected-remix"
        )
        measurements.append(contentsOf: residualMeasurements(
            source: canonicalReference,
            sum: rawRemix,
            prefix: "corrected-remix-difference.canonical-to-raw"
        ))
        measurements.append(contentsOf: residualMeasurements(
            source: canonicalReference,
            sum: correctedRemix,
            prefix: "corrected-remix-difference.canonical-to-corrected"
        ))
        measurements.append(contentsOf: residualMeasurements(
            source: rawRemix,
            sum: correctedRemix,
            prefix: "corrected-remix-difference.raw-to-corrected"
        ))
        measurements.append(contentsOf: correlationMeasurements(
            reference: canonicalReference,
            candidate: rawRemix,
            prefix: "corrected-remix-correlation.canonical-to-raw"
        ))
        measurements.append(contentsOf: correlationMeasurements(
            reference: canonicalReference,
            candidate: correctedRemix,
            prefix: "corrected-remix-correlation.canonical-to-corrected"
        ))
        measurements.append(contentsOf: correlationMeasurements(
            reference: rawRemix,
            candidate: correctedRemix,
            prefix: "corrected-remix-correlation.raw-to-corrected"
        ))
        if let stereoCorrelation = normalizedCorrelation(
            correctedRemix.channels[0],
            correctedRemix.channels[1]
        ) {
            measurements.append(
                StemValidationMeasurement(
                    id: "corrected-remix.stereo-correlation",
                    value: stereoCorrelation,
                    unit: "ratio"
                )
            )
        }

        let bandValidation = validateCorrectedRemixComparisonBands(
            canonicalReference: canonicalReference,
            rawRemix: rawRemix,
            correctedRemix: correctedRemix
        )
        failures.append(contentsOf: bandValidation.failures)
        measurements.append(contentsOf: bandValidation.measurements)

        let noiseValidation = validateCorrectedRemixNoise(context: noiseContext)
        failures.append(contentsOf: noiseValidation.failures)
        measurements.append(contentsOf: noiseValidation.measurements)

        return finalizedResult(
            phase: .correctedPureSum,
            failedChecks: failures,
            measurements: measurements
        )
    }

    /// 補正済み純粋加算と、ユーザーが確定した再ミックス設定の描画結果を比較します。
    ///
    /// gain・pan・帯域ducking・共通reverbによる音楽的な差は合否に使わず、
    /// 構造、有限値、ピーク測定、残差、相関だけを記録します。
    func validateProcessedRemix(
        correctedPureSum: AudioSignal,
        remixed: AudioSignal,
        expectedSampleRate: Double,
        expectedChannelCount: Int
    ) -> StemValidationResult {
        var failures = validateExpectedStereoContract(expectedChannelCount)
        failures.append(contentsOf: validateExpectedSampleRateContract(expectedSampleRate))
        failures.append(contentsOf: validateSignal(
            correctedPureSum,
            subject: "corrected-pure-sum",
            expectedSampleRate: expectedSampleRate,
            expectedChannelCount: expectedChannelCount,
            expectedFrameCount: nil
        ))
        failures.append(contentsOf: validateSignal(
            remixed,
            subject: "stem-remix",
            expectedSampleRate: expectedSampleRate,
            expectedChannelCount: expectedChannelCount,
            expectedFrameCount: correctedPureSum.frameCount
        ))
        guard failures.isEmpty else {
            return StemValidationResult(
                phase: .processedRemix,
                failedChecks: failures,
                measurements: []
            )
        }

        var measurements = peakMeasurements(signal: remixed, prefix: "stem-remix")
        measurements.append(contentsOf: residualMeasurements(
            source: correctedPureSum,
            sum: remixed,
            prefix: "stem-remix-difference.pure-sum-to-remix"
        ))
        measurements.append(contentsOf: correlationMeasurements(
            reference: correctedPureSum,
            candidate: remixed,
            prefix: "stem-remix-correlation.pure-sum-to-remix"
        ))
        if let stereoCorrelation = normalizedCorrelation(
            remixed.channels[0],
            remixed.channels[1]
        ) {
            measurements.append(StemValidationMeasurement(
                id: "stem-remix.stereo-correlation",
                value: stereoCorrelation,
                unit: "ratio"
            ))
        }
        return finalizedResult(
            phase: .processedRemix,
            failedChecks: failures,
            measurements: measurements
        )
    }

    private func validateExpectedSampleRateContract(
        _ expectedSampleRate: Double
    ) -> [StemValidationFailure] {
        guard expectedSampleRate.isFinite, expectedSampleRate > 0 else {
            return [
                StemValidationFailure(
                    check: .sampleRate,
                    subject: "validation-contract",
                    detail: "期待sample rateは0より大きい有限値が必要です（実際: \(expectedSampleRate)）"
                )
            ]
        }
        return []
    }

    private func validateComparisonBands(
        reference: AudioSignal,
        remix: AudioSignal
    ) -> (failures: [StemValidationFailure], measurements: [StemValidationMeasurement]) {
        var failures: [StemValidationFailure] = []
        let referenceBands = analyzeComparisonBands(
            signal: reference,
            subject: "reference",
            failures: &failures
        )
        let remixBands = analyzeComparisonBands(
            signal: remix,
            subject: "raw-remix",
            failures: &failures
        )

        guard let referenceBands, let remixBands else {
            return (failures, [])
        }

        let referenceLevels = validatedBandLevels(
            referenceBands,
            subject: "reference",
            failures: &failures
        )
        let remixLevels = validatedBandLevels(
            remixBands,
            subject: "raw-remix",
            failures: &failures
        )
        let measurements = Self.comparisonBandIDs.compactMap { id -> StemValidationMeasurement? in
            guard let referenceLevel = referenceLevels[id],
                  let remixLevel = remixLevels[id]
            else { return nil }
            let difference = remixLevel - referenceLevel
            guard difference.isFinite else {
                failures.append(
                    StemValidationFailure(
                        check: .bandEnergies,
                        subject: "remix-band-difference.\(id)",
                        detail: "band energy差分が有限値ではありません"
                    )
                )
                return nil
            }
            return StemValidationMeasurement(
                id: "remix-band-difference.\(id)",
                value: difference,
                unit: "dB"
            )
        }
        return (failures, measurements)
    }

    private func validateCorrectedRemixComparisonBands(
        canonicalReference: AudioSignal,
        rawRemix: AudioSignal,
        correctedRemix: AudioSignal
    ) -> (failures: [StemValidationFailure], measurements: [StemValidationMeasurement]) {
        var failures: [StemValidationFailure] = []
        let canonicalBands = analyzeComparisonBands(
            signal: canonicalReference,
            subject: "canonical-input",
            failures: &failures
        )
        let rawBands = analyzeComparisonBands(
            signal: rawRemix,
            subject: "raw-remix",
            failures: &failures
        )
        let correctedBands = analyzeComparisonBands(
            signal: correctedRemix,
            subject: "corrected-remix",
            failures: &failures
        )

        guard let canonicalBands, let rawBands, let correctedBands else {
            return (failures, [])
        }

        let canonicalLevels = validatedBandLevels(
            canonicalBands,
            subject: "canonical-input",
            failures: &failures
        )
        let rawLevels = validatedBandLevels(
            rawBands,
            subject: "raw-remix",
            failures: &failures
        )
        let correctedLevels = validatedBandLevels(
            correctedBands,
            subject: "corrected-remix",
            failures: &failures
        )

        var measurements: [StemValidationMeasurement] = []
        measurements.append(contentsOf: bandDifferenceMeasurements(
            from: canonicalLevels,
            to: rawLevels,
            prefix: "corrected-remix-band-difference.canonical-to-raw",
            failures: &failures
        ))
        measurements.append(contentsOf: bandDifferenceMeasurements(
            from: canonicalLevels,
            to: correctedLevels,
            prefix: "corrected-remix-band-difference.canonical-to-corrected",
            failures: &failures
        ))
        measurements.append(contentsOf: bandDifferenceMeasurements(
            from: rawLevels,
            to: correctedLevels,
            prefix: "corrected-remix-band-difference.raw-to-corrected",
            failures: &failures
        ))
        return (failures, measurements)
    }

    private func bandDifferenceMeasurements(
        from referenceLevels: [String: Double],
        to candidateLevels: [String: Double],
        prefix: String,
        failures: inout [StemValidationFailure]
    ) -> [StemValidationMeasurement] {
        Self.comparisonBandIDs.compactMap { id -> StemValidationMeasurement? in
            guard let referenceLevel = referenceLevels[id],
                  let candidateLevel = candidateLevels[id]
            else { return nil }
            let difference = candidateLevel - referenceLevel
            guard difference.isFinite else {
                failures.append(
                    StemValidationFailure(
                        check: .bandEnergies,
                        subject: "\(prefix).\(id)",
                        detail: "band energy差分が有限値ではありません"
                    )
                )
                return nil
            }
            return StemValidationMeasurement(
                id: "\(prefix).\(id)",
                value: difference,
                unit: "dB"
            )
        }
    }

    private func analyzeComparisonBands(
        signal: AudioSignal,
        subject: String,
        failures: inout [StemValidationFailure]
    ) -> [BandEnergyMetric]? {
        do {
            return try comparisonBandAnalyzer(signal)
        } catch {
            failures.append(
                StemValidationFailure(
                    check: .audioComparison,
                    subject: subject,
                    detail: "AudioComparisonServiceの分析に失敗しました: \(error.localizedDescription)"
                )
            )
            return nil
        }
    }

    private func validatedBandLevels(
        _ bands: [BandEnergyMetric],
        subject: String,
        failures: inout [StemValidationFailure]
    ) -> [String: Double] {
        let expectedIDs = Set(Self.comparisonBandIDs)
        let grouped = Dictionary(grouping: bands, by: \.id)

        for id in grouped.keys.sorted() where !expectedIDs.contains(id) {
            failures.append(
                StemValidationFailure(
                    check: .bandEnergies,
                    subject: "\(subject).\(id)",
                    detail: "契約にないband energy IDです"
                )
            )
        }

        var levels: [String: Double] = [:]
        for id in Self.comparisonBandIDs {
            guard let matches = grouped[id] else {
                failures.append(
                    StemValidationFailure(
                        check: .bandEnergies,
                        subject: "\(subject).\(id)",
                        detail: "band energy測定値がありません"
                    )
                )
                continue
            }
            guard matches.count == 1 else {
                failures.append(
                    StemValidationFailure(
                        check: .bandEnergies,
                        subject: "\(subject).\(id)",
                        detail: "band energy測定値が重複しています（実際: \(matches.count)）"
                    )
                )
                continue
            }
            guard let level = matches.first?.levelDB, level.isFinite else {
                failures.append(
                    StemValidationFailure(
                        check: .bandEnergies,
                        subject: "\(subject).\(id)",
                        detail: "band energy測定値が有限値ではありません"
                    )
                )
                continue
            }
            levels[id] = level
        }
        return levels
    }

    private func validateRemixNoise(
        context: StemRemixNoiseValidationContext
    ) -> (failures: [StemValidationFailure], measurements: [StemValidationMeasurement]) {
        var failures: [StemValidationFailure] = []
        let referenceLevels = validatedNoiseLevels(
            context.canonicalInput,
            subject: "canonical-input",
            failures: &failures
        )
        let remixLevels = validatedNoiseLevels(
            context.rawRemix,
            subject: "raw-remix",
            failures: &failures
        )

        var measurements: [StemValidationMeasurement] = []
        for id in Self.noiseMeasurementIDs {
            guard let reference = referenceLevels[id], let remix = remixLevels[id] else { continue }
            let delta = remix - reference
            measurements.append(
                StemValidationMeasurement(
                    id: "remix-noise.\(id).reference",
                    value: reference,
                    unit: "dB"
                )
            )
            measurements.append(
                StemValidationMeasurement(
                    id: "remix-noise.\(id).remix",
                    value: remix,
                    unit: "dB"
                )
            )
            guard delta.isFinite else {
                failures.append(
                    StemValidationFailure(
                        check: .noiseMeasurements,
                        subject: "remix-noise.\(id).delta",
                        detail: "noise差分が有限値ではありません"
                    )
                )
                continue
            }
            measurements.append(
                StemValidationMeasurement(
                    id: "remix-noise.\(id).delta",
                    value: delta,
                    unit: "dB"
                )
            )
        }
        return (failures, measurements)
    }

    private func validateCorrectedRemixNoise(
        context: StemCorrectedRemixNoiseValidationContext
    ) -> (failures: [StemValidationFailure], measurements: [StemValidationMeasurement]) {
        var failures: [StemValidationFailure] = []
        let canonicalLevels = validatedNoiseLevels(
            context.canonicalInput,
            subject: "canonical-input",
            failures: &failures
        )
        let rawLevels = validatedNoiseLevels(
            context.rawRemix,
            subject: "raw-remix",
            failures: &failures
        )
        let correctedLevels = validatedNoiseLevels(
            context.correctedPureSum,
            subject: "corrected-remix",
            failures: &failures
        )

        var measurements: [StemValidationMeasurement] = []
        for id in Self.noiseMeasurementIDs {
            guard let canonical = canonicalLevels[id],
                  let raw = rawLevels[id],
                  let corrected = correctedLevels[id]
            else { continue }
            let prefix = "corrected-remix-noise.\(id)"
            measurements.append(
                StemValidationMeasurement(
                    id: "\(prefix).canonical",
                    value: canonical,
                    unit: "dB"
                )
            )
            measurements.append(
                StemValidationMeasurement(
                    id: "\(prefix).raw",
                    value: raw,
                    unit: "dB"
                )
            )
            measurements.append(
                StemValidationMeasurement(
                    id: "\(prefix).corrected",
                    value: corrected,
                    unit: "dB"
                )
            )
            appendFiniteNoiseDelta(
                raw - canonical,
                id: "\(prefix).raw-minus-canonical",
                failures: &failures,
                measurements: &measurements
            )
            appendFiniteNoiseDelta(
                corrected - canonical,
                id: "\(prefix).corrected-minus-canonical",
                failures: &failures,
                measurements: &measurements
            )
            appendFiniteNoiseDelta(
                corrected - raw,
                id: "\(prefix).corrected-minus-raw",
                failures: &failures,
                measurements: &measurements
            )
        }
        return (failures, measurements)
    }

    private func appendFiniteNoiseDelta(
        _ delta: Double,
        id: String,
        failures: inout [StemValidationFailure],
        measurements: inout [StemValidationMeasurement]
    ) {
        guard delta.isFinite else {
            failures.append(
                StemValidationFailure(
                    check: .noiseMeasurements,
                    subject: id,
                    detail: "noise差分が有限値ではありません"
                )
            )
            return
        }
        measurements.append(
            StemValidationMeasurement(
                id: id,
                value: delta,
                unit: "dB"
            )
        )
    }

    private func validatedNoiseLevels(
        _ snapshot: NoiseMeasurementSnapshot,
        subject: String,
        failures: inout [StemValidationFailure]
    ) -> [String: Double] {
        let expectedIDs = Set(Self.noiseMeasurementIDs)
        let grouped = Dictionary(grouping: snapshot.values, by: \.id)

        for id in grouped.keys.sorted() where !expectedIDs.contains(id) {
            failures.append(
                StemValidationFailure(
                    check: .noiseMeasurements,
                    subject: "\(subject).\(id)",
                    detail: "契約にないnoise measurement IDです"
                )
            )
        }

        var levels: [String: Double] = [:]
        for id in Self.noiseMeasurementIDs {
            guard let matches = grouped[id] else {
                failures.append(
                    StemValidationFailure(
                        check: .noiseMeasurements,
                        subject: "\(subject).\(id)",
                        detail: "noise測定値がありません"
                    )
                )
                continue
            }
            guard matches.count == 1 else {
                failures.append(
                    StemValidationFailure(
                        check: .noiseMeasurements,
                        subject: "\(subject).\(id)",
                        detail: "noise測定値が重複しています（実際: \(matches.count)）"
                    )
                )
                continue
            }
            guard let value = matches.first,
                  value.comparableLevelDB.isFinite,
                  value.measuredLevelDB.isFinite
            else {
                failures.append(
                    StemValidationFailure(
                        check: .noiseMeasurements,
                        subject: "\(subject).\(id)",
                        detail: "noise測定値が有限値ではありません"
                    )
                )
                continue
            }
            levels[id] = value.comparableLevelDB
        }
        return levels
    }

    private func validateExpectedStereoContract(
        _ expectedChannelCount: Int
    ) -> [StemValidationFailure] {
        guard expectedChannelCount == 2 else {
            return [
                StemValidationFailure(
                    check: .channelCount,
                    subject: "validation-contract",
                    detail: "Stem Modeの検証契約はstereo 2 channelです（実際: \(expectedChannelCount)）"
                )
            ]
        }
        return []
    }

    private func finalizedResult(
        phase: StemValidationPhase,
        failedChecks: [StemValidationFailure],
        measurements: [StemValidationMeasurement]
    ) -> StemValidationResult {
        var failures = failedChecks
        var finiteMeasurements: [StemValidationMeasurement] = []
        for measurement in measurements {
            guard measurement.value.isFinite else {
                failures.append(
                    StemValidationFailure(
                        check: .finiteMeasurements,
                        subject: measurement.id,
                        detail: "測定結果が有限値ではありません"
                    )
                )
                continue
            }
            finiteMeasurements.append(measurement)
        }
        return StemValidationResult(
            phase: phase,
            failedChecks: failures,
            measurements: finiteMeasurements
        )
    }

    private func validateSignal(
        _ signal: AudioSignal,
        subject: String,
        expectedSampleRate: Double,
        expectedChannelCount: Int,
        expectedFrameCount: Int?
    ) -> [StemValidationFailure] {
        var failures: [StemValidationFailure] = []

        if !signal.sampleRate.isFinite || signal.sampleRate != expectedSampleRate {
            failures.append(
                StemValidationFailure(
                    check: .sampleRate,
                    subject: subject,
                    detail: "期待: \(expectedSampleRate)、実際: \(signal.sampleRate)"
                )
            )
        }
        if signal.channels.count != expectedChannelCount {
            failures.append(
                StemValidationFailure(
                    check: .channelCount,
                    subject: subject,
                    detail: "期待: \(expectedChannelCount)、実際: \(signal.channels.count)"
                )
            )
        }

        guard let firstChannel = signal.channels.first, !firstChannel.isEmpty else {
            failures.append(
                StemValidationFailure(
                    check: .channelFrameCounts,
                    subject: subject,
                    detail: "音声フレームがありません"
                )
            )
            return failures
        }

        if let expectedFrameCount, firstChannel.count != expectedFrameCount {
            failures.append(
                StemValidationFailure(
                    check: .channelFrameCounts,
                    subject: subject,
                    detail: "期待フレーム: \(expectedFrameCount)、実際: \(firstChannel.count)"
                )
            )
        }
        for (channelIndex, channel) in signal.channels.enumerated() {
            if channel.count != firstChannel.count {
                failures.append(
                    StemValidationFailure(
                        check: .channelFrameCounts,
                        subject: "\(subject).channel.\(channelIndex)",
                        detail: "channel 0: \(firstChannel.count)、実際: \(channel.count)"
                    )
                )
            }
            if channel.contains(where: { !$0.isFinite }) {
                failures.append(
                    StemValidationFailure(
                        check: .finiteSamples,
                        subject: "\(subject).channel.\(channelIndex)",
                        detail: "NaNまたはInfinityがあります"
                    )
                )
            }
        }
        return failures
    }

    private func sumSignals(
        _ signals: [StemRole: AudioSignal],
        order: [StemRole]
    ) -> AudioSignal? {
        guard let firstRole = order.first,
              let reference = signals[firstRole]
        else { return nil }

        var channels = Array(
            repeating: Array(repeating: Float.zero, count: reference.frameCount),
            count: reference.channels.count
        )
        for role in order {
            guard let signal = signals[role] else { return nil }
            for channelIndex in channels.indices {
                for frameIndex in channels[channelIndex].indices {
                    channels[channelIndex][frameIndex] += signal.channels[channelIndex][frameIndex]
                }
            }
        }
        return AudioSignal(channels: channels, sampleRate: reference.sampleRate)
    }

    private func containsNonFiniteSample(_ signal: AudioSignal) -> Bool {
        signal.channels.contains { channel in
            channel.contains { !$0.isFinite }
        }
    }

    private func peakMeasurements(signal: AudioSignal, prefix: String) -> [StemValidationMeasurement] {
        let samplePeak = signal.channels.reduce(Float.zero) { currentPeak, channel in
            channel.reduce(currentPeak) { max($0, abs($1)) }
        }
        let truePeak = LoudnessMeasurementService.truePeakLinear(signal.channels)
        let overRangeCount = signal.channels.reduce(0) { count, channel in
            count + channel.reduce(0) { $0 + (abs($1) > 1 ? 1 : 0) }
        }
        return [
            StemValidationMeasurement(
                id: "\(prefix).sample-peak",
                value: Double(samplePeak),
                unit: "linear"
            ),
            StemValidationMeasurement(
                id: "\(prefix).true-peak",
                value: Double(truePeak),
                unit: "linear"
            ),
            StemValidationMeasurement(
                id: "\(prefix).over-range-samples",
                value: Double(overRangeCount),
                unit: "samples"
            )
        ]
    }

    private func residualMeasurements(
        source: AudioSignal,
        sum: AudioSignal,
        prefix: String = "stem-sum-residual"
    ) -> [StemValidationMeasurement] {
        var squareSum = 0.0
        var peak = 0.0
        var sampleCount = 0
        for channelIndex in source.channels.indices {
            for frameIndex in source.channels[channelIndex].indices {
                let residual = Double(source.channels[channelIndex][frameIndex])
                    - Double(sum.channels[channelIndex][frameIndex])
                squareSum += residual * residual
                peak = max(peak, abs(residual))
                sampleCount += 1
            }
        }
        let rms = sampleCount > 0 ? sqrt(squareSum / Double(sampleCount)) : 0
        return [
            StemValidationMeasurement(id: "\(prefix).rms", value: rms, unit: "linear"),
            StemValidationMeasurement(id: "\(prefix).peak", value: peak, unit: "linear")
        ]
    }

    private func correlationMeasurements(
        reference: AudioSignal,
        candidate: AudioSignal,
        prefix: String = "reference-candidate-correlation"
    ) -> [StemValidationMeasurement] {
        reference.channels.indices.compactMap { channelIndex in
            guard let value = normalizedCorrelation(
                reference.channels[channelIndex],
                candidate.channels[channelIndex]
            ) else { return nil }
            return StemValidationMeasurement(
                id: "\(prefix).channel.\(channelIndex)",
                value: value,
                unit: "ratio"
            )
        }
    }

    // Same normalized dot-product definition already used by AudioComparisonService.
    // A silent channel has no meaningful correlation, so no measurement is emitted.
    private func normalizedCorrelation(_ lhs: [Float], _ rhs: [Float]) -> Double? {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return nil }
        var lhsEnergy = 0.0
        var rhsEnergy = 0.0
        var sharedEnergy = 0.0
        for index in lhs.indices {
            let left = Double(lhs[index])
            let right = Double(rhs[index])
            lhsEnergy += left * left
            rhsEnergy += right * right
            sharedEnergy += left * right
        }
        let denominator = sqrt(lhsEnergy * rhsEnergy)
        guard denominator > 1e-12 else { return nil }
        return max(-1, min(1, sharedEnergy / denominator))
    }
}
