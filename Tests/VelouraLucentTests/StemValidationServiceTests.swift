import Foundation
import Testing
@testable import VelouraLucent

struct StemValidationServiceTests {
    private let service = StemValidationService()

    @Test
    func exactFourStemSumProducesZeroResidualAndPerfectCorrelation() throws {
        let stems = exactStems()
        let source = try StemMixService().pureSum(stems: stems).signal

        let result = service.validateSeparatedStems(
            source: source,
            stems: Array(stems.reversed()),
            expectedSampleRate: 44_100,
            expectedChannelCount: 2
        )

        #expect(result.passed)
        #expect(result.failedChecks.isEmpty)
        #expect(result.measurement(id: "stem-sum-residual.rms")?.value == 0)
        #expect(result.measurement(id: "stem-sum-residual.peak")?.value == 0)
        #expect(result.measurement(id: "reference-candidate-correlation.channel.0")?.value == 1)
        #expect(result.measurement(id: "reference-candidate-correlation.channel.1")?.value == 1)
    }

    @Test
    func exactSixStemContractValidatesEveryRoleAndUsesTheExplicitFloat32Order() throws {
        let profile = StemProductionModelProfile.profile(for: .bsRoformerSW)
        let stems = profile.sourceOrder.enumerated().map { index, role in
            let value = Float(index + 1) * 0.01
            return StemMixInput(
                role: role,
                signal: AudioSignal(
                    channels: [[value, -value], [-value, value]],
                    sampleRate: 44_100
                )
            )
        }
        let source = try StemMixService().pureSum(
            stems: stems,
            validationRoles: profile.sourceOrder,
            order: profile.pureSumOrder
        ).signal

        let result = service.validateSeparatedStems(
            source: source,
            stems: Array(stems.reversed()),
            validationRoles: profile.sourceOrder,
            pureSumOrder: profile.pureSumOrder,
            expectedSampleRate: 44_100,
            expectedChannelCount: 2
        )

        #expect(result.passed)
        #expect(result.measurement(id: "stem.guitar.sample-peak") != nil)
        #expect(result.measurement(id: "stem.piano.sample-peak") != nil)
        #expect(result.measurement(id: "stem-sum-residual.peak")?.value == 0)
    }

    @Test
    func sixStemDuplicateMissingAndNonFiniteRolesFailStructuralValidation() {
        let profile = StemProductionModelProfile.profile(for: .bsRoformerSW)
        let signal = AudioSignal(channels: [[0.1, 0.2], [0.1, 0.2]], sampleRate: 44_100)
        var stems = profile.sourceOrder.map { StemMixInput(role: $0, signal: signal) }
        stems[5] = StemMixInput(
            role: .guitar,
            signal: AudioSignal(channels: [[0.1, .nan], [0.1, 0.2]], sampleRate: 44_100)
        )

        let result = service.validateSeparatedStems(
            source: signal,
            stems: stems,
            validationRoles: profile.sourceOrder,
            pureSumOrder: profile.pureSumOrder,
            expectedSampleRate: 44_100,
            expectedChannelCount: 2
        )

        #expect(!result.passed)
        #expect(result.failedCheckKinds.contains(.roleCoverage))
        #expect(result.failedCheckKinds.contains(.finiteSamples))
        #expect(result.failedChecks.contains { $0.subject == StemRole.piano.rawValue })
    }

    @Test
    func structuralFailuresAreReturnedTogetherInsteadOfHidingTheFirstIssue() {
        var stems = exactStems()
        stems.removeLast()
        stems[1] = StemMixInput(
            role: .drums,
            signal: AudioSignal(
                channels: [[0, .nan], [0]],
                sampleRate: 48_000
            )
        )
        let source = AudioSignal(channels: [[0, 0], [0, 0]], sampleRate: 44_100)

        let result = service.validateSeparatedStems(
            source: source,
            stems: stems,
            expectedSampleRate: 44_100,
            expectedChannelCount: 2
        )

        #expect(!result.passed)
        #expect(!result.canContinue)
        #expect(result.failedCheckKinds.contains(.stemCount))
        #expect(result.failedCheckKinds.contains(.roleCoverage))
        #expect(result.failedCheckKinds.contains(.channelFrameCounts))
        #expect(result.failedCheckKinds.contains(.sampleRate))
        #expect(result.failedCheckKinds.contains(.finiteSamples))
        #expect(result.measurements.isEmpty)
    }

    @Test
    func NonZeroResidualIsMeasuredWithoutAnUncalibratedPassFailThreshold() {
        let stems = exactStems()
        let source = AudioSignal(
            channels: [[0.5, -0.25, 0.125], [-0.5, 0.25, -0.125]],
            sampleRate: 44_100
        )

        let result = service.validateSeparatedStems(
            source: source,
            stems: stems,
            expectedSampleRate: 44_100,
            expectedChannelCount: 2
        )

        #expect(result.passed)
        #expect((result.measurement(id: "stem-sum-residual.rms")?.value ?? 0) > 0)
        #expect((result.measurement(id: "stem-sum-residual.peak")?.value ?? 0) > 0)
        #expect(!result.failedCheckKinds.contains(.residual))
    }

    @Test
    func finiteRemixOverRangeIsRecordedAndDoesNotFailValidation() {
        let reference = AudioSignal(
            channels: [[1.4, -1.4, 0.2], [-1.25, 1.25, -0.2]],
            sampleRate: 48_000
        )

        let result = service.validateRemix(
            reference: reference,
            remix: reference,
            noiseContext: noiseContext(),
            expectedSampleRate: 48_000,
            expectedChannelCount: 2
        )

        #expect(result.passed)
        #expect(abs((result.measurement(id: "raw-remix.sample-peak")?.value ?? 0) - 1.4) < 0.000_001)
        #expect(result.measurement(id: "raw-remix.over-range-samples")?.value == 4)
    }

    @Test
    func remixLengthAndFormatMismatchesFailBeforeMeasurements() {
        let reference = AudioSignal(channels: [[0, 0], [0, 0]], sampleRate: 48_000)
        let remix = AudioSignal(channels: [[0, 0, 0]], sampleRate: 44_100)

        let result = service.validateRemix(
            reference: reference,
            remix: remix,
            noiseContext: noiseContext(),
            expectedSampleRate: 48_000,
            expectedChannelCount: 2
        )

        #expect(!result.passed)
        #expect(!result.canContinue)
        #expect(result.failedCheckKinds.contains(.sampleRate))
        #expect(result.failedCheckKinds.contains(.channelCount))
        #expect(result.failedCheckKinds.contains(.channelFrameCounts))
        #expect(result.measurements.isEmpty)
    }

    @Test
    func correctedRemixRecordsCanonicalRawAndCorrectedMeasurements() throws {
        let canonical = stereoSignal(amplitude: 0.20)
        let raw = stereoSignal(amplitude: 0.10)
        let corrected = stereoSignal(amplitude: 0.05)

        let result = service.validateCorrectedRemix(
            canonicalReference: canonical,
            rawRemix: raw,
            correctedRemix: corrected,
            noiseContext: correctedNoiseContext(
                canonicalBase: -70,
                rawBase: -68,
                correctedBase: -65
            ),
            expectedSampleRate: 44_100,
            expectedChannelCount: 2
        )

        #expect(result.phase == .correctedPureSum)
        #expect(result.passed)
        #expect((result.measurement(id: "corrected-remix.sample-peak")?.value ?? 0) > 0)
        #expect(result.measurement(
            id: "corrected-remix-difference.canonical-to-raw.rms"
        ) != nil)
        #expect(result.measurement(
            id: "corrected-remix-difference.canonical-to-corrected.rms"
        ) != nil)
        #expect(result.measurement(
            id: "corrected-remix-difference.raw-to-corrected.rms"
        ) != nil)
        #expect(result.measurement(
            id: "corrected-remix-correlation.canonical-to-corrected.channel.0"
        ) != nil)

        for prefix in [
            "corrected-remix-band-difference.canonical-to-raw.",
            "corrected-remix-band-difference.canonical-to-corrected.",
            "corrected-remix-band-difference.raw-to-corrected.",
        ] {
            let bandMeasurements = result.measurements.filter { $0.id.hasPrefix(prefix) }
            #expect(bandMeasurements.count == AudioBandCatalog.comparisonBands.count)
            #expect(bandMeasurements.allSatisfy { $0.value.isFinite && $0.unit == "dB" })
        }

        #expect(result.measurement(id: "corrected-remix-noise.hiss.canonical")?.value == -70)
        #expect(result.measurement(id: "corrected-remix-noise.hiss.raw")?.value == -68)
        #expect(result.measurement(id: "corrected-remix-noise.hiss.corrected")?.value == -65)
        #expect(result.measurement(
            id: "corrected-remix-noise.hiss.corrected-minus-raw"
        )?.value == 3)
    }

    @Test
    func correctedRemixStructuralFailureStopsBeforeMeasurements() {
        let canonical = stereoSignal(amplitude: 0.20)
        let raw = stereoSignal(amplitude: 0.10)
        let corrected = AudioSignal(
            channels: [[0.1, -0.1]],
            sampleRate: 48_000
        )

        let result = service.validateCorrectedRemix(
            canonicalReference: canonical,
            rawRemix: raw,
            correctedRemix: corrected,
            noiseContext: correctedNoiseContext(),
            expectedSampleRate: 44_100,
            expectedChannelCount: 2
        )

        #expect(result.phase == .correctedPureSum)
        #expect(!result.passed)
        #expect(!result.canContinue)
        #expect(result.failedCheckKinds.contains(.sampleRate))
        #expect(result.failedCheckKinds.contains(.channelCount))
        #expect(result.failedCheckKinds.contains(.channelFrameCounts))
        #expect(result.measurements.isEmpty)
    }

    @Test
    func correctedRemixMeasurementsDoNotMakeTheMusicalSelectionDecision() throws {
        let canonical = stereoSignal(amplitude: 0.15)
        let raw = canonical
        let corrected = AudioSignal(
            channels: canonical.channels.map { channel in channel.map { -$0 } },
            sampleRate: canonical.sampleRate
        )

        let result = service.validateCorrectedRemix(
            canonicalReference: canonical,
            rawRemix: raw,
            correctedRemix: corrected,
            noiseContext: correctedNoiseContext(
                canonicalBase: -70,
                rawBase: -70,
                correctedBase: -20
            ),
            expectedSampleRate: 44_100,
            expectedChannelCount: 2
        )

        let correlation = try #require(result.measurement(
            id: "corrected-remix-correlation.raw-to-corrected.channel.0"
        )?.value)
        #expect(result.passed)
        #expect(abs(correlation + 1) < 0.000_001)
        #expect((result.measurement(
            id: "corrected-remix-difference.raw-to-corrected.rms"
        )?.value ?? 0) > 0)
        #expect(result.measurement(
            id: "corrected-remix-noise.hiss.corrected-minus-raw"
        )?.value == 50)
        #expect(!result.failedCheckKinds.contains(.residual))
        #expect(!result.failedCheckKinds.contains(.correlation))
    }

    @Test
    func nonStereoExpectedContractFailsBeforeStereoMeasurements() {
        let mono = AudioSignal(channels: [[0.1, -0.1]], sampleRate: 44_100)
        let stems = StemRole.allCases.map { role in
            StemMixInput(role: role, signal: mono)
        }

        let separated = service.validateSeparatedStems(
            source: mono,
            stems: stems,
            expectedSampleRate: 44_100,
            expectedChannelCount: 1
        )
        let remix = service.validateRemix(
            reference: mono,
            remix: mono,
            noiseContext: noiseContext(),
            expectedSampleRate: 44_100,
            expectedChannelCount: 1
        )

        #expect(!separated.passed)
        #expect(separated.failedCheckKinds.contains(.channelCount))
        #expect(separated.measurements.isEmpty)
        #expect(!remix.passed)
        #expect(remix.failedCheckKinds.contains(.channelCount))
        #expect(remix.measurements.isEmpty)
    }

    @Test
    func nonFiniteTruePeakMeasurementFailsWithoutPersistingInfinity() throws {
        let maximum = Float.greatestFiniteMagnitude
        let zero = AudioSignal(channels: [[0, 0], [0, 0]], sampleRate: 44_100)
        let positive = AudioSignal(
            channels: [[maximum, maximum], [maximum, maximum]],
            sampleRate: 44_100
        )
        let negative = AudioSignal(
            channels: [[-maximum, -maximum], [-maximum, -maximum]],
            sampleRate: 44_100
        )
        let stems = [
            StemMixInput(role: .vocals, signal: zero),
            StemMixInput(role: .drums, signal: positive),
            StemMixInput(role: .bass, signal: negative),
            StemMixInput(role: .other, signal: zero)
        ]

        let result = service.validateSeparatedStems(
            source: zero,
            stems: stems,
            expectedSampleRate: 44_100,
            expectedChannelCount: 2
        )

        #expect(!result.passed)
        #expect(!result.canContinue)
        #expect(result.failedCheckKinds.contains(.finiteMeasurements))
        #expect(result.measurement(id: "stem.drums.true-peak") == nil)
        #expect(result.measurements.allSatisfy { $0.value.isFinite })
    }

    @Test
    func residualUsesDoubleSubtractionBeforeMeasuringExtremeFiniteSamples() {
        let positive = Float(3.0e38)
        let negative = -positive
        let source = AudioSignal(channels: [[positive], [positive]], sampleRate: 44_100)
        let zero = AudioSignal(channels: [[0], [0]], sampleRate: 44_100)
        let stems = [
            StemMixInput(
                role: .vocals,
                signal: AudioSignal(channels: [[negative], [negative]], sampleRate: 44_100)
            ),
            StemMixInput(role: .drums, signal: zero),
            StemMixInput(role: .bass, signal: zero),
            StemMixInput(role: .other, signal: zero)
        ]

        let result = service.validateSeparatedStems(
            source: source,
            stems: stems,
            expectedSampleRate: 44_100,
            expectedChannelCount: 2
        )

        let residualPeak = result.measurement(id: "stem-sum-residual.peak")?.value
        #expect(result.passed)
        #expect(residualPeak?.isFinite == true)
        #expect((residualPeak ?? 0) > 5.9e38)
    }

    @Test
    func remixRecordsCatalogBandDifferencesWithoutThresholdFailure() throws {
        let reference = stereoSignal(amplitude: 0.20)
        let remix = stereoSignal(amplitude: 0.10)

        let result = service.validateRemix(
            reference: reference,
            remix: remix,
            noiseContext: noiseContext(),
            expectedSampleRate: 44_100,
            expectedChannelCount: 2
        )

        let expectedIDs = AudioBandCatalog.comparisonBands.map { "remix-band-difference.\($0.id)" }
        let bandMeasurements = result.measurements.filter { $0.id.hasPrefix("remix-band-difference.") }
        #expect(result.passed)
        #expect(bandMeasurements.map(\.id) == expectedIDs)
        #expect(bandMeasurements.count == AudioBandCatalog.comparisonBands.count)
        #expect(bandMeasurements.allSatisfy { $0.value.isFinite && $0.unit == "dB" })
        #expect(!result.failedCheckKinds.contains(.bandEnergies))
    }

    @Test
    func remixRecordsReferenceRemixAndDeltaForFullNoiseSnapshots() throws {
        let context = noiseContext(beforeBase: -70, afterBase: -68.5)
        let signal = stereoSignal(amplitude: 0.10)

        let result = service.validateRemix(
            reference: signal,
            remix: signal,
            noiseContext: context,
            expectedSampleRate: 44_100,
            expectedChannelCount: 2
        )

        let noiseIDs = ["hiss", "sibilance", "shimmer", "mud", "hum", "rumble", "room"]
        for id in noiseIDs {
            #expect(result.measurement(id: "remix-noise.\(id).reference")?.value == -70)
            #expect(result.measurement(id: "remix-noise.\(id).remix")?.value == -68.5)
            #expect(result.measurement(id: "remix-noise.\(id).delta")?.value == 1.5)
        }
        #expect(result.passed)
        #expect(!result.failedCheckKinds.contains(.noiseMeasurements))
    }

    @Test
    func malformedBandMeasurementsProduceTypedFailureAndNoFabricatedDelta() {
        let malformedBands = [
            band(id: "rumble", levelDB: -40),
            band(id: "rumble", levelDB: -41),
            band(id: "mud", levelDB: .nan),
            band(id: "core", levelDB: -20),
            band(id: "presence", levelDB: -30),
            band(id: "sparkle", levelDB: -40),
            band(id: "air", levelDB: -50),
            band(id: "ultraAir", levelDB: -60),
            band(id: "unexpected", levelDB: -10)
        ]
        let malformedService = StemValidationService(comparisonBandAnalyzer: { _ in malformedBands })
        let signal = stereoSignal(amplitude: 0.10)

        let result = malformedService.validateRemix(
            reference: signal,
            remix: signal,
            noiseContext: noiseContext(),
            expectedSampleRate: 44_100,
            expectedChannelCount: 2
        )

        #expect(!result.passed)
        #expect(result.canContinue)
        #expect(result.failedCheckKinds.contains(.bandEnergies))
        #expect(result.measurement(id: "remix-band-difference.rumble") == nil)
        #expect(result.measurement(id: "remix-band-difference.warmth") == nil)
        #expect(result.measurement(id: "remix-band-difference.mud") == nil)
        #expect(result.measurements.allSatisfy { $0.value.isFinite })
    }

    @Test
    func malformedNoiseMeasurementsProduceTypedFailureAndNoFabricatedValues() {
        let before = NoiseMeasurementSnapshot(values: [
            noise(id: "hiss", value: -70),
            noise(id: "hiss", value: -71),
            noise(id: "sibilance", value: .infinity),
            noise(id: "shimmer", value: -72),
            noise(id: "mud", value: -73),
            noise(id: "hum", value: -74),
            noise(id: "rumble", value: -75),
            noise(id: "unexpected", value: -76)
        ])
        let signal = stereoSignal(amplitude: 0.10)

        let result = service.validateRemix(
            reference: signal,
            remix: signal,
            noiseContext: StemRemixNoiseValidationContext(
                canonicalInput: before,
                rawRemix: noiseSnapshot(value: -68)
            ),
            expectedSampleRate: 44_100,
            expectedChannelCount: 2
        )

        #expect(!result.passed)
        #expect(result.canContinue)
        #expect(result.failedCheckKinds.contains(.noiseMeasurements))
        #expect(result.measurement(id: "remix-noise.hiss.reference") == nil)
        #expect(result.measurement(id: "remix-noise.sibilance.reference") == nil)
        #expect(result.measurement(id: "remix-noise.room.reference") == nil)
        #expect(result.measurements.allSatisfy { $0.value.isFinite })
    }

    @Test
    func audioComparisonFailureIsAValidationFailure() {
        struct TestError: Error {}
        let failingService = StemValidationService(comparisonBandAnalyzer: { _ in throw TestError() })
        let signal = stereoSignal(amplitude: 0.10)

        let result = failingService.validateRemix(
            reference: signal,
            remix: signal,
            noiseContext: noiseContext(),
            expectedSampleRate: 44_100,
            expectedChannelCount: 2
        )

        #expect(!result.passed)
        #expect(result.canContinue)
        #expect(result.failedCheckKinds.contains(.audioComparison))
        #expect(result.measurements.contains { $0.id.hasPrefix("remix-band-difference.") } == false)
    }

    @Test
    func nonFiniteComputedDeltasProduceTypedFailuresWithoutPersistingInfinity() {
        let analyzer = StemValidationService(comparisonBandAnalyzer: { signal in
            let level = signal.channels[0][1] > 0.009
                ? -Double.greatestFiniteMagnitude
                : Double.greatestFiniteMagnitude
            return AudioBandCatalog.comparisonBands.map {
                BandEnergyMetric(
                    id: $0.id,
                    label: $0.label,
                    rangeDescription: $0.rangeDescription,
                    levelDB: level
                )
            }
        })
        let reference = stereoSignal(amplitude: 0.20)
        let remix = stereoSignal(amplitude: 0.10)

        let result = analyzer.validateRemix(
            reference: reference,
            remix: remix,
            noiseContext: noiseContext(
                beforeBase: -Double.greatestFiniteMagnitude,
                afterBase: Double.greatestFiniteMagnitude
            ),
            expectedSampleRate: 44_100,
            expectedChannelCount: 2
        )

        #expect(!result.passed)
        #expect(result.canContinue)
        #expect(result.failedCheckKinds.contains(.bandEnergies))
        #expect(result.failedCheckKinds.contains(.noiseMeasurements))
        #expect(result.measurement(id: "remix-band-difference.rumble") == nil)
        #expect(result.measurement(id: "remix-noise.hiss.delta") == nil)
        #expect(result.measurements.allSatisfy { $0.value.isFinite })
    }

    @Test(arguments: [0.0, -44_100.0, .infinity, .nan])
    func invalidExpectedSampleRateAlwaysFailsValidation(expectedSampleRate: Double) {
        let signal = AudioSignal(channels: [[0.1, -0.1], [0.1, -0.1]], sampleRate: expectedSampleRate)
        let stems = StemRole.allCases.map { StemMixInput(role: $0, signal: signal) }

        let separated = service.validateSeparatedStems(
            source: signal,
            stems: stems,
            expectedSampleRate: expectedSampleRate,
            expectedChannelCount: 2
        )
        let remix = service.validateRemix(
            reference: signal,
            remix: signal,
            noiseContext: noiseContext(),
            expectedSampleRate: expectedSampleRate,
            expectedChannelCount: 2
        )

        #expect(!separated.passed)
        #expect(separated.failedCheckKinds.contains(.sampleRate))
        #expect(!remix.passed)
        #expect(remix.failedCheckKinds.contains(.sampleRate))
    }

    private func exactStems() -> [StemMixInput] {
        [
            StemMixInput(
                role: .drums,
                signal: AudioSignal(channels: [[0.1, 0.2, -0.1], [-0.1, 0.2, 0.1]], sampleRate: 44_100)
            ),
            StemMixInput(
                role: .bass,
                signal: AudioSignal(channels: [[0.05, -0.05, 0.1], [0.05, 0.05, -0.1]], sampleRate: 44_100)
            ),
            StemMixInput(
                role: .other,
                signal: AudioSignal(channels: [[-0.02, 0.03, 0.04], [0.02, -0.03, -0.04]], sampleRate: 44_100)
            ),
            StemMixInput(
                role: .vocals,
                signal: AudioSignal(channels: [[0.25, -0.1, 0.05], [-0.25, 0.1, -0.05]], sampleRate: 44_100)
            )
        ]
    }

    private func stereoSignal(amplitude: Float) -> AudioSignal {
        let frames = (0..<2_048).map { index in
            amplitude * sin(2 * .pi * 440 * Float(index) / 44_100)
        }
        return AudioSignal(channels: [frames, frames], sampleRate: 44_100)
    }

    private func noiseContext(
        beforeBase: Double = -70,
        afterBase: Double = -70
    ) -> StemRemixNoiseValidationContext {
        StemRemixNoiseValidationContext(
            canonicalInput: noiseSnapshot(value: beforeBase),
            rawRemix: noiseSnapshot(value: afterBase)
        )
    }

    private func correctedNoiseContext(
        canonicalBase: Double = -70,
        rawBase: Double = -70,
        correctedBase: Double = -70
    ) -> StemCorrectedRemixNoiseValidationContext {
        StemCorrectedRemixNoiseValidationContext(
            canonicalInput: noiseSnapshot(value: canonicalBase),
            rawRemix: noiseSnapshot(value: rawBase),
            correctedPureSum: noiseSnapshot(value: correctedBase)
        )
    }

    private func noiseSnapshot(value: Double) -> NoiseMeasurementSnapshot {
        NoiseMeasurementSnapshot(values: [
            noise(id: "hiss", value: value),
            noise(id: "sibilance", value: value),
            noise(id: "shimmer", value: value),
            noise(id: "mud", value: value),
            noise(id: "hum", value: value),
            noise(id: "rumble", value: value),
            noise(id: "room", value: value)
        ])
    }

    private func noise(id: String, value: Double) -> NoiseMeasurementValue {
        NoiseMeasurementValue(
            id: id,
            label: id,
            comparableLevelDB: value,
            measuredLevelDB: value
        )
    }

    private func band(id: String, levelDB: Double) -> BandEnergyMetric {
        BandEnergyMetric(id: id, label: id, rangeDescription: "test", levelDB: levelDB)
    }
}
