import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

struct AudioAnalysisModeTests {
    @Test
    func experimentalMetalAnalysisFallsBackToCPUOutput() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "analysis-mode-input.wav")
        let cpuOutputURL = tempDirectory.appending(path: "analysis-mode-cpu.wav")
        let metalOutputURL = tempDirectory.appending(path: "analysis-mode-metal.wav")

        try makeTestTone(at: inputURL, duration: 2)

        let processor = NativeAudioProcessor()
        try processor.process(
            inputFile: inputURL,
            outputFile: cpuOutputURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu
        )
        try processor.process(
            inputFile: inputURL,
            outputFile: metalOutputURL,
            denoiseStrength: .balanced,
            analysisMode: .experimentalMetal
        )

        let cpuData = try Data(contentsOf: cpuOutputURL)
        let metalData = try Data(contentsOf: metalOutputURL)
        #expect(cpuData == metalData)
    }

    private func makeTestTone(at url: URL, duration: Double) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let base = Float(sin(2 * Double.pi * 330 * time) * 0.11)
            let high = Float(sin(2 * Double.pi * 7_200 * time) * 0.025)
            left[index] = base + high
            right[index] = base * 0.94 - high * 0.35
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 2)
        )
        try file.write(from: buffer)
    }
}
