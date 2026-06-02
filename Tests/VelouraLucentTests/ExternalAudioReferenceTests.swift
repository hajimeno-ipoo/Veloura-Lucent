import Foundation
import Testing
@testable import VelouraLucent

struct ExternalAudioReferenceTests {
    @Test
    func fixedAudioQualityFixturesStayNearFFmpegEBUR128Reference() throws {
        let fixtureNames = [
            "bright_air_reference.wav",
            "hiss_under_music.wav",
            "mixed_mastering_reference.wav",
            "short_shimmer_bursts.wav"
        ]

        for fixtureName in fixtureNames {
            let url = try audioQualityFixtureURL(fixtureName)
            try expectAppLoudnessAndPeakNearFFmpegReference(
                fileURL: url,
                label: fixtureName,
                lufsTolerance: 1.0,
                truePeakTolerance: 0.3
            )
        }
    }

    @Test
    func fixedAudioQualityFixturesWithStableLRAStayNearFFmpegEBUR128Reference() throws {
        let fixtures: [ExternalAudioReferenceCase] = [
            ExternalAudioReferenceCase(fileName: "hiss_under_music.wav", lraTolerance: 0.5),
            ExternalAudioReferenceCase(fileName: "mixed_mastering_reference.wav", lraTolerance: 1.0)
        ]

        for fixture in fixtures {
            let url = try audioQualityFixtureURL(fixture.fileName)
            try expectAppLRANearFFmpegReference(
                fileURL: url,
                label: fixture.fileName,
                lraTolerance: fixture.lraTolerance
            )
        }
    }

    @Test
    func realAudioExcerptStaysNearFFmpegEBUR128Reference() throws {
        let projectDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceURL = projectDirectory.appending(path: "violin #002 睡眠.wav")
        let sourceSignal = try AudioFileService.loadAudio(from: sourceURL)
        let excerpt = try audioQualityExcerpt(from: sourceSignal, startSeconds: 60, durationSeconds: 8)
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let excerptURL = tempDirectory.appending(path: "real-audio-external-reference.wav")
        try AudioFileService.saveAudio(excerpt, to: excerptURL)

        try expectAppMeasurementNearFFmpegReference(
            fileURL: excerptURL,
            label: "violin #002 睡眠.wav 60s-68s",
            lufsTolerance: 1.0,
            lraTolerance: 2.5,
            truePeakTolerance: 0.3
        )
    }

    private func expectAppLoudnessAndPeakNearFFmpegReference(
        fileURL: URL,
        label: String,
        lufsTolerance: Double,
        truePeakTolerance: Double
    ) throws {
        let external = try FFmpegEBUR128Reference.measure(fileURL: fileURL)
        let app = try AudioComparisonService.analyze(fileURL: fileURL)
        let lufsDelta = app.integratedLoudnessLUFS - external.integratedLoudnessLUFS
        let truePeakDelta = app.truePeakDBFS - external.truePeakDBFS

        #expect(
            abs(lufsDelta) <= lufsTolerance,
            "\(label) LUFS delta \(format(lufsDelta)); app \(format(app.integratedLoudnessLUFS)), ffmpeg \(format(external.integratedLoudnessLUFS))"
        )
        #expect(
            abs(truePeakDelta) <= truePeakTolerance,
            "\(label) true peak delta \(format(truePeakDelta)); app \(format(app.truePeakDBFS)), ffmpeg \(format(external.truePeakDBFS))"
        )
    }

    private func expectAppLRANearFFmpegReference(
        fileURL: URL,
        label: String,
        lraTolerance: Double
    ) throws {
        let external = try FFmpegEBUR128Reference.measure(fileURL: fileURL)
        let app = try AudioComparisonService.analyze(fileURL: fileURL)
        let lraDelta = app.loudnessRangeLU - external.loudnessRangeLU

        #expect(
            abs(lraDelta) <= lraTolerance,
            "\(label) LRA delta \(format(lraDelta)); app \(format(app.loudnessRangeLU)), ffmpeg \(format(external.loudnessRangeLU))"
        )
    }

    private func expectAppMeasurementNearFFmpegReference(
        fileURL: URL,
        label: String,
        lufsTolerance: Double,
        lraTolerance: Double,
        truePeakTolerance: Double
    ) throws {
        let external = try FFmpegEBUR128Reference.measure(fileURL: fileURL)
        let app = try AudioComparisonService.analyze(fileURL: fileURL)
        let lufsDelta = app.integratedLoudnessLUFS - external.integratedLoudnessLUFS
        let lraDelta = app.loudnessRangeLU - external.loudnessRangeLU
        let truePeakDelta = app.truePeakDBFS - external.truePeakDBFS

        #expect(
            abs(lufsDelta) <= lufsTolerance,
            "\(label) LUFS delta \(format(lufsDelta)); app \(format(app.integratedLoudnessLUFS)), ffmpeg \(format(external.integratedLoudnessLUFS))"
        )
        #expect(
            abs(lraDelta) <= lraTolerance,
            "\(label) LRA delta \(format(lraDelta)); app \(format(app.loudnessRangeLU)), ffmpeg \(format(external.loudnessRangeLU))"
        )
        #expect(
            abs(truePeakDelta) <= truePeakTolerance,
            "\(label) true peak delta \(format(truePeakDelta)); app \(format(app.truePeakDBFS)), ffmpeg \(format(external.truePeakDBFS))"
        )
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

private struct ExternalAudioReferenceCase {
    let fileName: String
    let lraTolerance: Double
}

private struct FFmpegEBUR128Measurement {
    let integratedLoudnessLUFS: Double
    let loudnessRangeLU: Double
    let truePeakDBFS: Double
}

private enum FFmpegEBUR128Reference {
    static func measure(fileURL: URL) throws -> FFmpegEBUR128Measurement {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        process.arguments = [
            "-hide_banner",
            "-nostats",
            "-i",
            fileURL.path(percentEncoded: false),
            "-filter_complex",
            "ebur128=peak=true",
            "-f",
            "null",
            "-"
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combinedOutput = output + "\n" + errorOutput
        guard process.terminationStatus == 0 else {
            throw FFmpegEBUR128ReferenceError.commandFailed(combinedOutput)
        }

        return try parse(combinedOutput)
    }

    private static func parse(_ output: String) throws -> FFmpegEBUR128Measurement {
        guard let summaryRange = output.range(of: "Summary:") else {
            throw FFmpegEBUR128ReferenceError.missingSummary(output)
        }
        let summary = String(output[summaryRange.lowerBound...])
        guard
            let integrated = firstMatch(in: summary, pattern: #"I:\s*([-0-9.]+)\s+LUFS"#),
            let lra = firstMatch(in: summary, pattern: #"LRA:\s*([-0-9.]+)\s+LU"#),
            let truePeak = firstMatch(in: summary, pattern: #"Peak:\s*([-0-9.]+)\s+dBFS"#)
        else {
            throw FFmpegEBUR128ReferenceError.missingValue(summary)
        }

        return FFmpegEBUR128Measurement(
            integratedLoudnessLUFS: integrated,
            loudnessRangeLU: lra,
            truePeakDBFS: truePeak
        )
    }

    private static func firstMatch(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            match.numberOfRanges >= 2,
            let valueRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Double(text[valueRange])
    }
}

private enum FFmpegEBUR128ReferenceError: Error, CustomStringConvertible {
    case commandFailed(String)
    case missingSummary(String)
    case missingValue(String)

    var description: String {
        switch self {
        case let .commandFailed(output):
            return "ffmpeg ebur128 failed: \(output)"
        case let .missingSummary(output):
            return "ffmpeg ebur128 summary was not found: \(output)"
        case let .missingValue(summary):
            return "ffmpeg ebur128 value was not found: \(summary)"
        }
    }
}
