import Foundation
import Testing
@testable import VelouraLucent

struct NoiseWorkflowVerificationTests {
    @Test
    func correctionAndMasteringNoiseWorkflowProducesReport() async throws {
        let inputURL = try audioQualityFixtureURL("mixed_mastering_reference.wav")

        let inputSignal = try AudioFileService.loadAudio(from: inputURL)
        let inputNoise = NoiseMeasurementService.analyze(signal: inputSignal)
        var rows: [NoiseWorkflowRow] = []

        for strength in DenoiseStrength.allCases {
            let correctedURL = try await AudioProcessingService().process(
                inputFile: inputURL,
                denoiseStrength: strength,
                correctionSettings: strength.settings,
                analysisMode: .cpu
            ) { _ in }
            #expect(FileManager.default.fileExists(atPath: correctedURL.path(percentEncoded: false)))
            let correctedSignal = try AudioFileService.loadAudio(from: correctedURL)
            let correctedNoise = NoiseMeasurementService.analyze(signal: correctedSignal)
            let masteredURL = try await MasteringService().process(
                inputFile: correctedURL,
                settings: MasteringProfile.streaming.settings,
                referenceNoiseMeasurements: correctedNoise,
                originalReferenceFile: inputURL,
                originalReferenceNoiseMeasurements: inputNoise
            ) { _ in }

            let masteredSignal = try AudioFileService.loadAudio(from: masteredURL)
            let masteredNoise = NoiseMeasurementService.analyze(signal: masteredSignal)

            rows.append(
                NoiseWorkflowRow(
                    strength: strength,
                    input: inputNoise,
                    corrected: correctedNoise,
                    mastered: masteredNoise,
                    correctedSignal: correctedSignal,
                    masteredSignal: masteredSignal
                )
            )

            #expect(FileManager.default.fileExists(atPath: masteredURL.path(percentEncoded: false)))
        }

        let report = makeReport(rows: rows)
        let reportURL = FileManager.default.temporaryDirectory.appending(path: "VelouraLucentNoiseWorkflowVerification.md")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)

        #expect(rows.count == DenoiseStrength.allCases.count)
        #expect(FileManager.default.fileExists(atPath: reportURL.path(percentEncoded: false)))
        #expect(rows.flatMap(\.allValues).allSatisfy { $0.isFinite })

        let gentle = try #require(rows.first { $0.strength == .gentle })
        let strong = try #require(rows.first { $0.strength == .strong })
        #expect(strong.value("hiss", in: strong.corrected) <= gentle.value("hiss", in: gentle.corrected) - 0.3)
        #expect(strong.value("shimmer", in: strong.corrected) <= gentle.value("shimmer", in: gentle.corrected) - 0.3)
        #expect(strong.value("hiss", in: strong.corrected) <= strong.value("hiss", in: strong.input))
        #expect(strong.value("shimmer", in: strong.corrected) <= strong.value("shimmer", in: strong.input))
        #expect(strong.value("hum", in: strong.corrected) <= strong.value("hum", in: strong.input) - 3.0)
        #expect(strong.value("rumble", in: strong.corrected) <= strong.value("rumble", in: strong.input) - 3.0)
        #expect(strong.value("room", in: strong.corrected) <= strong.value("room", in: strong.input) - 3.0)
        #expect((strong.value("hiss", in: strong.mastered) - strong.value("hiss", in: strong.corrected)).isFinite)
        expectAudioQualityHighBandsNotDulled(reference: inputSignal, processed: strong.correctedSignal)
        expectAudioQualityHighBandsNotDulled(reference: inputSignal, processed: strong.masteredSignal)
        #expect(strong.value("hiss", in: strong.mastered) <= strong.value("hiss", in: strong.corrected)
            + audioQualityMaxFinalHighNoiseReturnDB(for: NoiseMeasurementID.hiss))
        #expect(strong.value("shimmer", in: strong.mastered) <= strong.value("shimmer", in: strong.corrected)
            + audioQualityMaxFinalHighNoiseReturnDB(for: NoiseMeasurementID.shimmer))
        #expect(report.contains("| 強い | ヒス・シュワシュワ |") && report.contains("マスタリングで戻りすぎ"))
        #expect(report.contains("| 強い | サ行・歯擦音 |") && report.contains("補正の効きが弱い"))
    }

    private func makeReport(rows: [NoiseWorkflowRow]) -> String {
        let ids = ["hiss", "sibilance", "shimmer", "mud", "hum", "rumble", "room"]
        var lines: [String] = [
            "# Noise Workflow Verification",
            "",
            "- 比較基準: `NoiseMeasurementService` の音量補正済み dB",
            "- マスタリング: `MasteringProfile.streaming`",
            "- 判定: 数値が下がるほど、そのノイズ指標は減っています",
            "",
            "## 入力・補正後・マスタリング後",
            "",
            "| 強さ | 段階 | \(ids.map(label).joined(separator: " | ")) |",
            "| --- | --- | \(ids.map { _ in "---:" }.joined(separator: " | ")) |"
        ]

        for row in rows {
            lines.append(tableLine(strength: row.strength.title, stage: "入力", values: ids.map { row.value($0, in: row.input) }))
            lines.append(tableLine(strength: row.strength.title, stage: "補正後", values: ids.map { row.value($0, in: row.corrected) }))
            lines.append(tableLine(strength: row.strength.title, stage: "マスタリング後", values: ids.map { row.value($0, in: row.mastered) }))
        }

        lines += [
            "",
            "## 変化量",
            "",
            "| 強さ | 指標 | 補正での変化 | マスタリングで戻った量 | 判断 |",
            "| --- | --- | ---: | ---: | --- |"
        ]

        for row in rows {
            for id in ids {
                let correctionDelta = row.value(id, in: row.corrected) - row.value(id, in: row.input)
                let masteringDelta = row.value(id, in: row.mastered) - row.value(id, in: row.corrected)
                lines.append(
                    "| \(row.strength.title) | \(label(id)) | \(formatDB(correctionDelta)) | \(formatDB(masteringDelta)) | \(decision(correctionDelta: correctionDelta, masteringDelta: masteringDelta)) |"
                )
            }
        }

        lines += [
            "",
            "## 段階差",
            "",
            "| 指標 | 弱い→標準 | 標準→強い | 判断 |",
            "| --- | ---: | ---: | --- |"
        ]

        for id in ids {
            guard
                let gentle = rows.first(where: { $0.strength == .gentle }),
                let balanced = rows.first(where: { $0.strength == .balanced }),
                let strong = rows.first(where: { $0.strength == .strong })
            else { continue }
            let gentleToBalanced = balanced.value(id, in: balanced.corrected) - gentle.value(id, in: gentle.corrected)
            let balancedToStrong = strong.value(id, in: strong.corrected) - balanced.value(id, in: balanced.corrected)
            lines.append(
                "| \(label(id)) | \(formatDB(gentleToBalanced)) | \(formatDB(balancedToStrong)) | \(strengthDecision(gentleToBalanced: gentleToBalanced, balancedToStrong: balancedToStrong)) |"
            )
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func tableLine(strength: String, stage: String, values: [Double]) -> String {
        "| \(strength) | \(stage) | \(values.map(formatLevel).joined(separator: " | ")) |"
    }

    private func label(_ id: String) -> String {
        switch id {
        case "hiss":
            "ヒス・シュワシュワ"
        case "sibilance":
            "サ行・歯擦音"
        case "shimmer":
            "高域のチラつき"
        case "mud":
            "こもり・低いザラつき"
        case "hum":
            "ハム・電源ノイズ"
        case "rumble":
            "低域ゴロゴロ"
        case "room":
            "環境音・部屋鳴り"
        default:
            id
        }
    }

    private func formatLevel(_ value: Double) -> String {
        String(format: "%.1f dB", value)
    }

    private func formatDB(_ value: Double) -> String {
        String(format: "%+.1f dB", value)
    }

    private func decision(correctionDelta: Double, masteringDelta: Double) -> String {
        if correctionDelta >= -0.5 {
            return "補正の効きが弱い"
        }
        if masteringDelta > 2.0 {
            return "マスタリングで戻りすぎ"
        }
        return "許容"
    }

    private func strengthDecision(gentleToBalanced: Double, balancedToStrong: Double) -> String {
        if gentleToBalanced <= 0, balancedToStrong <= 0 {
            return "段階的に下がる"
        }
        return "段階差が不十分"
    }
}

private struct NoiseWorkflowRow {
    let strength: DenoiseStrength
    let input: NoiseMeasurementSnapshot
    let corrected: NoiseMeasurementSnapshot
    let mastered: NoiseMeasurementSnapshot
    let correctedSignal: AudioSignal
    let masteredSignal: AudioSignal

    var allValues: [Double] {
        [input, corrected, mastered].flatMap { snapshot in
            snapshot.values.flatMap { [$0.comparableLevelDB, $0.measuredLevelDB] }
        }
    }

    func value(_ id: String, in snapshot: NoiseMeasurementSnapshot) -> Double {
        snapshot.value(for: id)?.comparableLevelDB ?? -120
    }
}
