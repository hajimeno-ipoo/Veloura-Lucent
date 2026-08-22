import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

struct OfficialBS1770ValidationTests {
    @Test
    func ebuTech3341TruePeakTests15Through23FromOfficialFiles() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "ebu-loudness-test-setv05", directoryHint: .isDirectory)
        try #require(
            FileManager.default.fileExists(atPath: root.path(percentEncoded: false)),
            "EBU公式検証音源が見つかりません: \(root.path(percentEncoded: false))"
        )

        let expectedByTest = [
            15: -6.0,
            16: -6.0,
            17: -6.0,
            18: -6.0,
            19: 3.0,
            20: 0.0,
            21: 0.0,
            22: 0.0,
            23: 0.0,
        ]

        for testNumber in expectedByTest.keys.sorted() {
            let expected = try #require(expectedByTest[testNumber])
            let file = root.appending(path: "seq-3341-\(testNumber)-24bit.wav.wav")
            let signal = try AudioFileService.loadAudio(from: file)
            let linear = LoudnessMeasurementService.truePeakLinear(signal.channels)
            let actual = 20 * log10(max(Double(linear), 1e-12))
            let delta = actual - expected
            let passed = (-0.4...0.2).contains(delta)
            print(
                "EBU_TP_RESULT|test=\(testNumber)|expected=\(format(expected))|actual=\(format(actual))|delta=\(format(delta))|pass=\(passed)"
            )
            #expect(passed, "EBU Tech 3341 test \(testNumber): expected \(expected), actual \(actual)")
        }
    }

    @Test
    func ebuStandardMultichannelFileIsAutomaticallyConvertedToStereo() throws {
        let file = ebuStandardMultichannelFileURL()
        try #require(
            FileManager.default.fileExists(atPath: file.path(percentEncoded: false)),
            "EBU公式マルチチャンネル検証音源が見つかりません: \(file.path(percentEncoded: false))"
        )

        let signal = try AudioFileService.loadAudio(from: file)

        #expect(signal.channels.count == 2)
        #expect(signal.channels.allSatisfy { channel in
            channel.allSatisfy(\.isFinite)
        })
    }

    @Test
    func ebuStandardMultichannelFileCompletesNormalCorrectionAndMastering() async throws {
        let file = ebuStandardMultichannelFileURL()
        try #require(
            FileManager.default.fileExists(atPath: file.path(percentEncoded: false)),
            "EBU公式マルチチャンネル検証音源が見つかりません: \(file.path(percentEncoded: false))"
        )

        let corrected = try await AudioProcessingService().process(
            inputFile: file,
            logHandler: { _ in }
        )
        defer { PreviewFileStore.removeOwnedPreviewFileIfPresent(corrected) }
        let mastered = try await MasteringService().process(
            inputFile: corrected,
            settings: MasteringProfile.natural.settings,
            originalReferenceFile: file,
            logHandler: { _ in }
        )
        defer { PreviewFileStore.removeOwnedPreviewFileIfPresent(mastered) }

        let correctedSignal = try AudioFileService.loadAudio(from: corrected)
        let masteredSignal = try AudioFileService.loadAudio(from: mastered)
        #expect(correctedSignal.channels.count == 2)
        #expect(masteredSignal.channels.count == 2)
        #expect(correctedSignal.channels.allSatisfy { $0.allSatisfy(\.isFinite) })
        #expect(masteredSignal.channels.allSatisfy { $0.allSatisfy(\.isFinite) })
    }

    @Test
    func ebuStandardMultichannelFilePreparesStemCanonicalStereo() async throws {
        let file = ebuStandardMultichannelFileURL()
        try #require(
            FileManager.default.fileExists(atPath: file.path(percentEncoded: false)),
            "EBU公式マルチチャンネル検証音源が見つかりません: \(file.path(percentEncoded: false))"
        )
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "veloura-ebu-stem-input-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appending(path: "canonical-input.wav")

        _ = try await AudioInputConversionService().prepare(
            inputURL: file,
            outputURL: output
        )

        let preparedFile = try AVAudioFile(forReading: output)
        #expect(preparedFile.processingFormat.channelCount == 2)
        #expect(abs(preparedFile.processingFormat.sampleRate - 44_100) < 0.5)
    }

    @Test
    func ebuTech3342LoudnessRangeTests1Through4FromOfficialFiles() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "ebu-loudness-test-setv05", directoryHint: .isDirectory)
        try #require(
            FileManager.default.fileExists(atPath: root.path(percentEncoded: false)),
            "EBU公式検証音源が見つかりません: \(root.path(percentEncoded: false))"
        )

        let expectedByTest = [1: 10.0, 2: 5.0, 3: 20.0, 4: 15.0]
        for testNumber in expectedByTest.keys.sorted() {
            let expected = try #require(expectedByTest[testNumber])
            let file = root.appending(path: "seq-3342-\(testNumber)-16bit.wav")
            let signal = try AudioFileService.loadAudio(from: file)
            let actual = try #require(LoudnessMeasurementService.loudnessRange(signal: signal))
            let passed = abs(actual - expected) <= 1.0
            print(
                "EBU_LRA_RESULT|test=\(testNumber)|expected=\(format(expected))|actual=\(format(actual))|delta=\(format(actual - expected))|pass=\(passed)"
            )
            #expect(passed, "EBU Tech 3342 test \(testNumber): expected \(expected), actual \(actual)")
        }
    }

    @Test
    func ituBS2217MonoStereoFileBasedLoudness() throws {
        let rootPath = try #require(
            ProcessInfo.processInfo.environment["VELOURA_ITU_BS2217_TEST_ROOT"],
            "ITU公式検証音源の保存先をVELOURA_ITU_BS2217_TEST_ROOTに設定してください。"
        )
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        try #require(
            FileManager.default.fileExists(atPath: root.path(percentEncoded: false)),
            "ITU公式検証音源の保存先が見つかりません: \(root.path(percentEncoded: false))"
        )
        let expectedByFile: [String: Double] = [
            "1770-2_Comp_RelGateTest.wav": -10.0,
            "1770-2_Comp_AbsGateTest.wav": -69.5,
            "1770-2_Comp_18LKFS_FrequencySweep.wav": -18.0,
            "1770-2_Comp_23LKFS_25Hz_2ch.wav": -23.0,
            "1770-2_Comp_23LKFS_100Hz_2ch.wav": -23.0,
            "1770-2_Comp_23LKFS_500Hz_2ch.wav": -23.0,
            "1770-2_Comp_23LKFS_1000Hz_2ch.wav": -23.0,
            "1770-2_Comp_23LKFS_2000Hz_2ch.wav": -23.0,
            "1770-2_Comp_23LKFS_10000Hz_2ch.wav": -23.0,
            "1770-2_Comp_24LKFS_25Hz_2ch.wav": -24.0,
            "1770-2_Comp_24LKFS_100Hz_2ch.wav": -24.0,
            "1770-2_Comp_24LKFS_500Hz_2ch.wav": -24.0,
            "1770-2_Comp_24LKFS_1000Hz_2ch.wav": -24.0,
            "1770-2_Comp_24LKFS_2000Hz_2ch.wav": -24.0,
            "1770-2_Comp_24LKFS_10000Hz_2ch.wav": -24.0,
        ]

        for fileName in expectedByFile.keys.sorted() {
            let expected = try #require(expectedByFile[fileName])
            let signal = try AudioFileService.loadAudio(from: root.appending(path: fileName))
            let actual = Double(LoudnessMeasurementService.integratedLoudness(signal: signal))
            let delta = actual - expected
            let passed = abs(delta) <= 0.1
            print(
                "ITU_RESULT|\(fileName)|expected=\(format(expected))|actual=\(format(actual))|delta=\(format(delta))|pass=\(passed)"
            )
            #expect(passed, "\(fileName): expected \(expected), actual \(actual), delta \(delta)")
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private func ebuStandardMultichannelFileURL() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "ebu-loudness-test-setv05", directoryHint: .isDirectory)
            .appending(path: "seq-3341-6-6channels-WAVEEX-16bit.wav")
    }
}
