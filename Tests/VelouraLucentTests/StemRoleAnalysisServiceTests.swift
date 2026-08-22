import Foundation
import Testing
@testable import VelouraLucent

struct StemRoleAnalysisServiceTests {
    @Test
    func analyzesEveryRoleDirectlyFromFortyEightKilohertzProcessingSignal() throws {
        let service = StemRoleAnalysisService()
        let source = makeStereoSignal(duration: 0.35)
        let originalChannels = source.channels

        for role in StemProductionModelProfile.profile(for: .htdemucs).sourceOrder {
            let snapshot = try service.analyze(
                role: role,
                processingSignal48000: source
            )

            #expect(snapshot.role == role)
            #expect(snapshot.authoritativeSampleRate == 48_000)
            #expect(snapshot.analysisSampleRate == 48_000)
            #expect(snapshot.authoritativeFrameCount == source.frameCount)
            #expect(snapshot.analysisFrameCount == snapshot.authoritativeFrameCount)
            #expect(snapshot.features.count == 4)
            #expect(Set(snapshot.features.map(\.feature)).count == 4)
            #expect(snapshot.features.allSatisfy { feature in
                feature.frameCount > 0
                    && feature.firstQuartile.isFinite
                    && feature.median.isFinite
                    && feature.thirdQuartile.isFinite
                    && feature.interquartileRange.isFinite
                    && feature.firstQuartile <= feature.median
                    && feature.median <= feature.thirdQuartile
                    && feature.interquartileRange >= 0
            })
        }

        #expect(source.sampleRate == 48_000)
        #expect(source.channels == originalChannels)
    }

    @Test
    func rejectsNonAuthoritativeRateMonoAndNonFiniteSamples() {
        let service = StemRoleAnalysisService()
        let valid = makeStereoSignal(duration: 0.05)

        #expect(
            throws: StemRoleAnalysisError.unsupportedAuthoritativeSampleRate(
                expected: 48_000,
                actual: 44_100
            )
        ) {
            try service.analyze(
                role: .vocals,
                processingSignal48000: AudioSignal(
                    channels: valid.channels,
                    sampleRate: 44_100
                )
            )
        }

        #expect(throws: StemRoleAnalysisError.stereoRequired(actualChannelCount: 1)) {
            try service.analyze(
                role: .drums,
                processingSignal48000: AudioSignal(
                    channels: [valid.channels[0]],
                    sampleRate: 48_000
                )
            )
        }

        var nonFinite = valid
        nonFinite.channels[1][3] = .nan
        #expect(
            throws: StemRoleAnalysisError.nonFiniteSample(
                channelIndex: 1,
                frameIndex: 3
            )
        ) {
            try service.analyze(role: .bass, processingSignal48000: nonFinite)
        }
    }

    @Test(
        "既存4roleの保護対象を同じ時間位置で過不足なく生成する",
        arguments: StemProductionModelProfile.profile(for: .htdemucs).sourceOrder
    )
    func producesTimeAlignedProtectionProfile(role: StemRole) throws {
        let signal = makeStereoSignal(duration: 0.35)
        let result = try StemRoleAnalysisService().analyzeWithProtection(
            role: role,
            processingSignal48000: signal
        )
        let profile = result.protectionProfile
        let expected = Set(StemRoleProtectedComponent.allCases.filter { $0.role == role })

        #expect(profile.role == role)
        #expect(profile.signalFrameCount == signal.frameCount)
        #expect(profile.analysisFrameSize == 4_096)
        #expect(profile.hopSize == 2_048)
        #expect(!profile.frames.isEmpty)
        #expect(profile.frames.allSatisfy { frame in
            Set(frame.values.keys) == expected
                && frame.values.values.allSatisfy(\.isFinite)
                && frame.startFrame >= 0
                && frame.validFrameCount > 0
        })
        #expect(profile.frames.last.map { $0.startFrame + $0.validFrameCount } == signal.frameCount)
    }

    @Test("GuitarとPianoは別々の専用解析と活動時系列を生成する", arguments: [
        StemRole.guitar,
        StemRole.piano,
    ])
    func analyzesDedicatedRolesWithoutOtherFeatures(role: StemRole) throws {
        let signal = makeStereoSignal(duration: 0.35)
        let result = try StemRoleAnalysisService().analyzeWithProtection(
            role: role,
            processingSignal48000: signal
        )
        let snapshot = result.snapshot
        let profile = result.protectionProfile
        let roleFeatures = Set(snapshot.features.map(\.feature))
        let otherFeatures: Set<StemRoleAnalysisFeature> = [
            .otherPolyphonicSpectralSpread,
            .otherTransientStrength,
            .otherAmbienceContinuity,
            .otherStereoSpatialBalance,
        ]
        let expectedComponents = Set(StemRoleProtectedComponent.allCases.filter { $0.role == role })

        #expect(snapshot.role == role)
        #expect(snapshot.activity?.hasActivity == true)
        #expect(snapshot.activity?.floorDecibelsFullScale == -70)
        #expect(snapshot.dedicatedMetrics != nil)
        #expect(roleFeatures.isDisjoint(with: otherFeatures))
        #expect(role == .guitar ? snapshot.features.count == 12 : snapshot.features.count == 14)
        #expect(snapshot.features.allSatisfy { $0.frameCount > 0 })
        #expect(profile.role == role)
        #expect(profile.analysisFrameSize == 4_096)
        #expect(profile.hopSize == 1_024)
        #expect(profile.frames.allSatisfy { frame in
            Set(frame.values.keys) == expectedComponents
                && frame.values.values.allSatisfy(\.isFinite)
        })
    }

    @Test("無音と微小残留はGuitar／Pianoの楽器特徴として扱わない", arguments: [
        StemRole.guitar,
        StemRole.piano,
    ])
    func dedicatedActivityGateRejectsSilenceAndResidual(role: StemRole) throws {
        let service = StemRoleAnalysisService()
        let silence = AudioSignal(
            channels: Array(repeating: Array(repeating: 0, count: 48_000), count: 2),
            sampleRate: 48_000
        )
        let source = makeStereoSignal(duration: 1)
        let residual = AudioSignal(
            channels: source.channels.map { channel in channel.map { $0 * 0.0001 } },
            sampleRate: 48_000
        )

        for signal in [silence, residual] {
            let result = try service.analyzeWithProtection(
                role: role,
                processingSignal48000: signal
            )
            let activity = try #require(result.snapshot.activity)
            let metrics = try #require(result.snapshot.dedicatedMetrics)

            #expect(activity.activeFrameCount == 0)
            #expect(activity.activeFraction == 0)
            #expect(metrics.detectedOnsetCount == 0)
            #expect(metrics.onsetEnergy90thPercentile == 0)
            #expect(result.protectionProfile.frames.allSatisfy { frame in
                frame.values.values.allSatisfy { $0 == 0 }
            })
        }
    }

    @Test("保存済み実Guitar／Piano A/Bの製品解析値を採用済み基準へ照合")
    func dedicatedRealABMetricsMatchApprovedReference() throws {
        guard ProcessInfo.processInfo.environment["VELOURA_RUN_STEM_ROLE_ANALYSIS_FIXTURES"] == "1" else {
            return
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".stem-model-cache/bs-roformer-sw/role-analysis", isDirectory: true)
        let cases = [
            "clean",
            "identity",
            "attack_reduction",
            "harmonic_reduction",
            "tail_gate",
            "high_reduction",
            "band_balance",
            "mono",
            "silence",
            "near_silence",
        ]

        for role in [StemRole.guitar, .piano] {
            var measured: [String: (StemRoleActivitySummary, StemDedicatedRoleMetrics)] = [:]
            var profiles: [String: StemRoleProtectionProfile] = [:]
            let roleName = role.rawValue
            let referenceURL = root.appendingPathComponent("\(roleName)-role-analysis-approved.json")
            let reference = try #require(
                try JSONSerialization.jsonObject(with: Data(contentsOf: referenceURL)) as? [String: Any]
            )
            let clean = try #require(reference["clean"] as? [String: Any])
            let degradations = try #require(reference["degradations"] as? [String: Any])

            for caseName in cases {
                let expected = caseName == "clean" || caseName == "identity"
                    ? clean
                    : try #require(degradations[caseName] as? [String: Any])
                let audioURL = root
                    .appendingPathComponent("\(roleName)-degradations-approved", isDirectory: true)
                    .appendingPathComponent("\(caseName).wav")
                let signal = try AudioFileService.loadAudio(from: audioURL)
                let result = try StemRoleAnalysisService().analyzeWithProtection(
                    role: role,
                    processingSignal48000: signal
                )
                let snapshot = result.snapshot
                let activity = try #require(snapshot.activity)
                let metrics = try #require(snapshot.dedicatedMetrics)
                measured[caseName] = (activity, metrics)
                profiles[caseName] = result.protectionProfile

                let context = "\(roleName)/\(caseName)"
                expectClose(activity.activeFraction, expectedNumber("active_fraction", in: expected), absolute: 0.025, label: "\(context)/active_fraction")
                expectClose(activity.thresholdDecibelsFullScale, expectedNumber("activity_threshold_dbfs", in: expected), absolute: 2.0, label: "\(context)/activity_threshold_dbfs")
                expectClose(metrics.onsetEnergy90thPercentile, expectedNumber("onset_energy_p90", in: expected), relative: 0.35, absolute: 0.000_01, label: "\(context)/onset_energy_p90")
                expectClose(metrics.attackCrest90thPercentileDecibels, expectedNumber("attack_crest_p90_db", in: expected), absolute: 1.5, label: "\(context)/attack_crest_p90_db")
                expectClose(metrics.harmonicEnergyRatioMedian, expectedNumber("harmonic_energy_ratio_median", in: expected), absolute: 0.09, label: "\(context)/harmonic_energy_ratio_median")
                expectClose(metrics.inharmonicityMedian, expectedNumber("inharmonicity_median", in: expected), absolute: 0.04, label: "\(context)/inharmonicity_median")
                expectClose(metrics.spectralCentroidMedianHertz, expectedNumber("spectral_centroid_median_hz", in: expected), absolute: 130, label: "\(context)/spectral_centroid_median_hz")
                expectClose(metrics.rolloff85MedianHertz, expectedNumber("rolloff85_median_hz", in: expected), absolute: 130, label: "\(context)/rolloff85_median_hz")
                expectClose(metrics.highBandRatio90thPercentile, expectedNumber("high_band_ratio_p90", in: expected), relative: 0.8, absolute: 0.000_02, label: "\(context)/high_band_ratio_p90")
                expectClose(metrics.lowBandRatioMedian, expectedNumber("low_band_ratio_median", in: expected), absolute: 0.08, label: "\(context)/low_band_ratio_median")
                expectClose(metrics.midBandRatioMedian, expectedNumber("mid_band_ratio_median", in: expected), absolute: 0.08, label: "\(context)/mid_band_ratio_median")
                expectClose(metrics.tailRMSRatioMedianDecibels, expectedNumber("tail_rms_ratio_median_db", in: expected), absolute: 4.0, label: "\(context)/tail_rms_ratio_median_db")
                expectClose(metrics.tailLowRatioMedianDecibels, expectedNumber("tail_low_ratio_median_db", in: expected), absolute: 4.0, label: "\(context)/tail_low_ratio_median_db")
                expectClose(metrics.tailMidRatioMedianDecibels, expectedNumber("tail_mid_ratio_median_db", in: expected), absolute: 4.0, label: "\(context)/tail_mid_ratio_median_db")
                // Piano高域は元の絶対量が極小で、44.1→48 kHz変換後にdB比が大きく動きます。
                // この10 dBは基準JSONとのsample-rate差の照合幅であり、製品guardの閾値ではありません。
                expectClose(metrics.tailHighRatioMedianDecibels, expectedNumber("tail_high_ratio_median_db", in: expected), absolute: 10.0, label: "\(context)/tail_high_ratio_median_db")
                expectClose(metrics.doubleDecaySlopeDeltaMedianDecibelsPerSecond, expectedNumber("double_decay_slope_delta_median_db_per_second", in: expected), absolute: 8.0, label: "\(context)/double_decay_slope_delta_median_db_per_second")
                expectClose(metrics.stereoSideRatio, expectedNumber("stereo_side_ratio", in: expected), absolute: 0.015, label: "\(context)/stereo_side_ratio")
                expectClose(metrics.stereoCorrelation, expectedNumber("stereo_correlation", in: expected), absolute: 0.02, label: "\(context)/stereo_correlation")
            }

            let cleanMeasured = try #require(measured["clean"])
            let identity = try #require(measured["identity"])
            let silence = try #require(measured["silence"])
            let nearSilence = try #require(measured["near_silence"])
            let harmonicReduction = try #require(measured["harmonic_reduction"])
            let tailGate = try #require(measured["tail_gate"])
            let mono = try #require(measured["mono"])

            #expect(identity.0 == cleanMeasured.0)
            #expect(identity.1 == cleanMeasured.1)
            #expect(silence.0.activeFrameCount == 0)
            #expect(nearSilence.0.activeFrameCount == 0)
            #expect(harmonicReduction.1.harmonicEnergyRatioMedian < cleanMeasured.1.harmonicEnergyRatioMedian)
            #expect(harmonicReduction.1.inharmonicityMedian > cleanMeasured.1.inharmonicityMedian)
            #expect(tailGate.1.tailLowRatioMedianDecibels < cleanMeasured.1.tailLowRatioMedianDecibels)
            #expect(tailGate.1.tailMidRatioMedianDecibels < cleanMeasured.1.tailMidRatioMedianDecibels)
            #expect(tailGate.1.tailHighRatioMedianDecibels < cleanMeasured.1.tailHighRatioMedianDecibels)
            #expect(mono.1.stereoSideRatio <= cleanMeasured.1.stereoSideRatio * 0.05)

            let attackComponent: StemRoleProtectedComponent = role == .guitar ? .guitarAttack : .pianoAttack
            let cleanProfile = try #require(profiles["clean"])
            let reducedProfile = try #require(profiles["attack_reduction"])
            let cleanAttack = cleanProfile.frames.map { $0.values[attackComponent] ?? 0 }
            let reducedAttack = reducedProfile.frames.map { $0.values[attackComponent] ?? 0 }
            let onsetFloor = percentileForTest(cleanAttack, probability: 0.8)
            let onsetIndices = cleanAttack.indices.filter { cleanAttack[$0] >= onsetFloor && cleanAttack[$0] > 0 }
            let matchedClean = percentileForTest(onsetIndices.map { cleanAttack[$0] }, probability: 0.5)
            let matchedReduced = percentileForTest(onsetIndices.map { reducedAttack[$0] }, probability: 0.5)
            #expect(matchedReduced <= matchedClean * 0.85)

            if role == .guitar {
                let highReduction = try #require(measured["high_reduction"])
                #expect(highReduction.1.highBandRatio90thPercentile < cleanMeasured.1.highBandRatio90thPercentile)
            } else {
                let bandBalance = try #require(measured["band_balance"])
                #expect(bandBalance.1.midBandRatioMedian < cleanMeasured.1.midBandRatioMedian)
            }
        }
    }

    private func expectedNumber(_ key: String, in dictionary: [String: Any]) -> Double {
        (dictionary[key] as? NSNumber)?.doubleValue ?? .nan
    }

    private func expectClose(
        _ actual: Double,
        _ expected: Double,
        relative: Double = 0,
        absolute: Double,
        label: String
    ) {
        let tolerance = max(absolute, abs(expected) * relative)
        guard actual.isFinite, expected.isFinite, abs(actual - expected) <= tolerance else {
            Issue.record(Comment(rawValue: "\(label): actual=\(actual), expected=\(expected), tolerance=\(tolerance)"))
            return
        }
    }

    private func percentileForTest(_ values: [Double], probability: Double) -> Double {
        let sorted = values.sorted()
        guard let first = sorted.first else { return 0 }
        guard sorted.count > 1 else { return first }
        let position = max(0, min(1, probability)) * Double(sorted.count - 1)
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        guard lower != upper else { return sorted[lower] }
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    private func makeStereoSignal(duration: Double) -> AudioSignal {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * duration)
        var left = Array(repeating: Float.zero, count: frameCount)
        var right = Array(repeating: Float.zero, count: frameCount)
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let envelope = 0.55 + 0.45 * sin(2 * .pi * 3.2 * time)
            let transient = index.isMultiple(of: 2_205) ? 0.45 : 0
            left[index] = Float(
                envelope * (
                    0.32 * sin(2 * .pi * 110 * time)
                        + 0.2 * sin(2 * .pi * 220 * time)
                        + 0.08 * sin(2 * .pi * 6_500 * time)
                ) + transient
            )
            right[index] = Float(
                envelope * (
                    0.3 * sin(2 * .pi * 110 * time + 0.03)
                        + 0.18 * sin(2 * .pi * 330 * time)
                        + 0.07 * sin(2 * .pi * 8_000 * time)
                ) + transient * 0.85
            )
        }
        return AudioSignal(channels: [left, right], sampleRate: sampleRate)
    }
}
