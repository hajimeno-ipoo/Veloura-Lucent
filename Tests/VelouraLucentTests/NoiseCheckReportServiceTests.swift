import Testing
@testable import VelouraLucent

struct NoiseCheckReportServiceTests {
    @Test
    func reportShowsInputCorrectedMasteredAndDeltas() throws {
        let input = snapshot(hiss: -58, sibilance: 10, shimmer: -58, mud: -5, hum: 8, rumble: -34, room: -40)
        let corrected = snapshot(hiss: -72, sibilance: 6, shimmer: -74, mud: -8, hum: 4, rumble: -48, room: -46)
        let mastered = snapshot(hiss: -62, sibilance: 9, shimmer: -68, mud: -7, hum: 5, rumble: -44, room: -43)

        let report = try #require(NoiseCheckReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: mastered,
            correctionSettings: DenoiseStrength.balanced.settings,
            settings: MasteringProfile.streaming.settings
        ))

        let hiss = try #require(report.rows.first { $0.id == "hiss" })
        #expect(hiss.input?.severity == .warning)
        #expect(hiss.corrected?.severity == .low)
        #expect(hiss.mastered?.severity == .caution)
        #expect(hiss.correctionDeltaDB == -14)
        #expect(hiss.masteringDeltaDB == 10)
        #expect(hiss.summaryText.contains("戻りあり"))
        #expect(hiss.correctionEffectText.contains("大きく改善"))
        #expect(hiss.masteringEffectText.contains("戻りあり"))
        #expect(hiss.recommendedActions.map(\.stage) == [.mastering])
        #expect(hiss.recommendedActions.first?.title.contains("エアー帯域") == true)
        #expect(hiss.recommendedActions.first?.currentValue == "0.48")
        #expect(hiss.recommendedActions.first?.recommendedValue != "0.48")
        #expect(report.recommendedActions.contains { $0.id == "hiss-mastering" })
        #expect(report.recommendedActions.count <= 3)
    }

    @Test
    func lowSeverityDoesNotShowAdvice() throws {
        let metrics = snapshot(hiss: -72, sibilance: 3, shimmer: -72, mud: -12, hum: 2, rumble: -48, room: -52)

        let report = try #require(NoiseCheckReportService.makeReport(
            input: metrics,
            corrected: metrics,
            mastered: metrics,
            correctionSettings: DenoiseStrength.gentle.settings,
            settings: MasteringProfile.natural.settings
        ))

        #expect(report.rows.allSatisfy { $0.recommendedActions.isEmpty })
        #expect(report.severity == .low)
    }

    @Test
    func resolvedNoiseUsesCurrentSeverityInsteadOfInputSeverity() throws {
        let input = snapshot(hiss: -57, sibilance: 3, shimmer: -72, mud: -12, hum: 2, rumble: -48, room: -52)
        let corrected = snapshot(hiss: -70, sibilance: 3, shimmer: -72, mud: -12, hum: 2, rumble: -48, room: -52)
        let mastered = snapshot(hiss: -71, sibilance: 3, shimmer: -72, mud: -12, hum: 2, rumble: -48, room: -52)

        let report = try #require(NoiseCheckReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: mastered,
            correctionSettings: DenoiseStrength.balanced.settings,
            settings: MasteringProfile.natural.settings
        ))

        let hiss = try #require(report.rows.first { $0.id == "hiss" })
        #expect(hiss.input?.severity == .warning)
        #expect(hiss.corrected?.severity == .low)
        #expect(hiss.mastered?.severity == .low)
        #expect(hiss.severity == .low)
        #expect(report.severity == .low)
    }

    @Test
    func correctedIssueUsesCorrectionAdviceOnly() throws {
        let input = snapshot(hiss: -72, sibilance: 3, shimmer: -72, mud: -12, hum: 2, rumble: -48, room: -52)
        let corrected = snapshot(hiss: -58, sibilance: 3, shimmer: -72, mud: -12, hum: 2, rumble: -48, room: -52)

        let report = try #require(NoiseCheckReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: nil,
            correctionSettings: DenoiseStrength.balanced.settings,
            settings: MasteringProfile.streaming.settings
        ))

        let hiss = try #require(report.rows.first { $0.id == "hiss" })
        #expect(hiss.recommendedActions.map(\.stage) == [.correction])
        #expect(hiss.recommendedActions.first?.title.contains("補正") == true)
        #expect(hiss.recommendedActions.first?.currentValue == "50%")
        #expect(hiss.recommendedActions.first?.recommendedValue != "50%")
    }

    @Test
    func improvedCorrectionDoesNotShowCorrectionAction() throws {
        let input = snapshot(hiss: -58, sibilance: 3, shimmer: -72, mud: -12, hum: 2, rumble: -48, room: -52)
        let corrected = snapshot(hiss: -64, sibilance: 3, shimmer: -72, mud: -12, hum: 2, rumble: -48, room: -52)

        let report = try #require(NoiseCheckReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: nil,
            correctionSettings: DenoiseStrength.balanced.settings,
            settings: MasteringProfile.streaming.settings
        ))

        let hiss = try #require(report.rows.first { $0.id == "hiss" })
        #expect(hiss.correctionDeltaDB == -6)
        #expect(hiss.recommendedActions.isEmpty)
    }

    @Test
    func shimmerRowIsReportedSeparatelyFromSibilance() throws {
        let metrics = snapshot(hiss: -72, sibilance: 3, shimmer: -62, mud: -12, hum: 2, rumble: -48, room: -52)

        let report = try #require(NoiseCheckReportService.makeReport(
            input: metrics,
            corrected: metrics,
            mastered: metrics,
            correctionSettings: DenoiseStrength.balanced.settings,
            settings: MasteringProfile.streaming.settings
        ))

        let sibilance = try #require(report.rows.first { $0.id == "sibilance" })
        let shimmer = try #require(report.rows.first { $0.id == "shimmer" })
        #expect(sibilance.label == "サ行・歯擦音")
        #expect(shimmer.label == "高域のチラつき")
        #expect(shimmer.severity == .caution)
    }

    @Test
    func displayScaleUsesFixedRangeInsteadOfRowMinMax() throws {
        let input = snapshot(hiss: -72, sibilance: 7.6, shimmer: -72, mud: -12, hum: 2, rumble: -48, room: -52)
        let corrected = snapshot(hiss: -72, sibilance: 7.7, shimmer: -72, mud: -12, hum: 2, rumble: -48, room: -52)
        let mastered = snapshot(hiss: -72, sibilance: 7.5, shimmer: -72, mud: -12, hum: 2, rumble: -48, room: -52)

        let report = try #require(NoiseCheckReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: mastered,
            correctionSettings: DenoiseStrength.balanced.settings,
            settings: MasteringProfile.streaming.settings
        ))

        let sibilance = try #require(report.rows.first { $0.id == "sibilance" })
        let inputRatio = sibilance.displayScale.ratio(for: sibilance.input?.levelDB)
        let correctedRatio = sibilance.displayScale.ratio(for: sibilance.corrected?.levelDB)
        let masteredRatio = sibilance.displayScale.ratio(for: sibilance.mastered?.levelDB)
        let ratios = [inputRatio, correctedRatio, masteredRatio]

        #expect(sibilance.displayScale == NoiseCheckDisplayScale(minimum: 0, maximum: 14))
        #expect((ratios.max() ?? 0) - (ratios.min() ?? 0) < 0.02)
    }

    @Test
    func displayScaleSoftensLargeDBFSReductionWithoutChangingMeasuredValues() throws {
        let input = snapshot(hiss: -101.8, sibilance: 3, shimmer: -72, mud: -12, hum: 2, rumble: -48, room: -52)
        let corrected = snapshot(hiss: -116.7, sibilance: 3, shimmer: -72, mud: -12, hum: 2, rumble: -48, room: -52)

        let report = try #require(NoiseCheckReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: nil,
            correctionSettings: DenoiseStrength.balanced.settings,
            settings: MasteringProfile.streaming.settings
        ))

        let hiss = try #require(report.rows.first { $0.id == "hiss" })
        let inputRatio = hiss.displayScale.ratio(for: hiss.input?.levelDB)
        let correctedRatio = hiss.displayScale.ratio(for: hiss.corrected?.levelDB)

        #expect(hiss.input?.measuredLevelDB == -101.8)
        #expect(hiss.corrected?.measuredLevelDB == -116.7)
        #expect(correctedRatio > 0.28)
        #expect(inputRatio - correctedRatio < 0.35)
    }

    @Test
    func dbfsNoiseDisplayScaleIncludesSeverityThresholds() throws {
        let report = try #require(NoiseCheckReportService.makeReport(
            input: snapshot(hiss: -58, sibilance: 3, shimmer: -58, mud: -12, hum: 2, rumble: -48, room: -52),
            corrected: nil,
            mastered: nil,
            correctionSettings: DenoiseStrength.gentle.settings,
            settings: MasteringProfile.natural.settings
        ))

        let hiss = try #require(report.rows.first { $0.id == "hiss" })
        let shimmer = try #require(report.rows.first { $0.id == "shimmer" })

        #expect(hiss.displayScale.maximum >= InternalAudioJudgementPolicy.severityLimit(for: "hiss")!.warningDB)
        #expect(shimmer.displayScale.maximum >= InternalAudioJudgementPolicy.severityLimit(for: "shimmer")!.warningDB)
        #expect(hiss.displayScale.ratio(for: -65) < hiss.displayScale.ratio(for: -58))
        #expect(shimmer.displayScale.ratio(for: -66) < shimmer.displayScale.ratio(for: -58))
    }

    @Test
    func adviceIsHiddenWhenRecommendedChangeWouldBeZero() throws {
        var correctionSettings = DenoiseStrength.strong.settings
        correctionSettings.noiseDetectionSensitivity = 1.0
        var masteringSettings = MasteringProfile.streaming.settings
        masteringSettings.highShelfGain = -0.20

        let input = snapshot(hiss: -72, sibilance: 3, shimmer: -72, mud: -12, hum: 2, rumble: -48, room: -52)
        let corrected = snapshot(hiss: -58, sibilance: 3, shimmer: -72, mud: -12, hum: 2, rumble: -48, room: -52)
        let mastered = snapshot(hiss: -56, sibilance: 3, shimmer: -72, mud: -12, hum: 2, rumble: -48, room: -52)

        let report = try #require(NoiseCheckReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: mastered,
            correctionSettings: correctionSettings,
            settings: masteringSettings
        ))

        let hiss = try #require(report.rows.first { $0.id == "hiss" })
        #expect(hiss.severity == .warning)
        #expect(hiss.recommendedActions.isEmpty)
        #expect(report.recommendedActions.allSatisfy { $0.currentValue != $0.recommendedValue })
    }

    @Test
    func missingNoiseBarsUseConsistentPlaceholderWidth() throws {
        let report = try #require(NoiseCheckReportService.makeReport(
            input: snapshot(hiss: -72, sibilance: 3, shimmer: -72, mud: -12, hum: 2, rumble: -48, room: -52),
            corrected: nil,
            mastered: nil,
            correctionSettings: DenoiseStrength.gentle.settings,
            settings: MasteringProfile.natural.settings
        ))

        let missingRatios = report.rows.map { $0.displayScale.ratio(for: nil) }
        #expect(Set(missingRatios).count == 1)
        #expect(missingRatios.allSatisfy { $0 == 0.62 })
    }

    @Test
    func rowsExplainNoiseDirectionForDisplay() throws {
        let report = try #require(NoiseCheckReportService.makeReport(
            input: snapshot(hiss: -72, sibilance: 3, shimmer: -72, mud: -12, hum: 2, rumble: -48, room: -52),
            corrected: nil,
            mastered: nil,
            correctionSettings: DenoiseStrength.gentle.settings,
            settings: MasteringProfile.natural.settings
        ))

        let hiss = try #require(report.rows.first { $0.id == "hiss" })
        let sibilance = try #require(report.rows.first { $0.id == "sibilance" })
        let mud = try #require(report.rows.first { $0.id == "mud" })

        #expect(hiss.displayDescription == "下がるほどノイズが少ない")
        #expect(sibilance.displayDescription.contains("下げすぎると声が丸くなる"))
        #expect(mud.displayDescription == "上がるとこもりやすい")
    }

    @Test
    func reportRequiresAtLeastOneStage() {
        #expect(NoiseCheckReportService.makeReport(
            input: nil,
            corrected: nil,
            mastered: nil,
            correctionSettings: DenoiseStrength.balanced.settings,
            settings: MasteringProfile.streaming.settings
        ) == nil)
    }

    private func snapshot(
        hiss: Double,
        sibilance: Double,
        shimmer: Double,
        mud: Double,
        hum: Double,
        rumble: Double,
        room: Double
    ) -> NoiseMeasurementSnapshot {
        NoiseMeasurementSnapshot(values: [
            value("hiss", "ヒス・シュワシュワ", hiss),
            value("sibilance", "サ行・歯擦音", sibilance),
            value("shimmer", "高域のチラつき", shimmer),
            value("mud", "こもり・低いザラつき", mud),
            value("hum", "ハム・電源ノイズ", hum),
            value("rumble", "低域ゴロゴロ", rumble),
            value("room", "環境音・部屋鳴り", room)
        ])
    }

    private func value(_ id: String, _ label: String, _ level: Double) -> NoiseMeasurementValue {
        NoiseMeasurementValue(id: id, label: label, comparableLevelDB: level, measuredLevelDB: level)
    }
}
