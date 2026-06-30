import AppKit
import Foundation
import Testing
@testable import VelouraLucent

struct InputAudioDropSupportTests {
    @Test
    func acceptsExistingAudioFileAndRejectsNonAudioTargets() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "veloura-drop-support-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let audioURL = directory.appending(path: "input.wav")
        let textURL = directory.appending(path: "notes.txt")
        let movieURL = directory.appending(path: "movie.mp4")
        try AudioFileService.saveAudio(testSignal(), to: audioURL)
        try "not audio".write(to: textURL, atomically: true, encoding: .utf8)
        try Data().write(to: movieURL)

        #expect(InputAudioDropSupport.isAcceptedAudioFile(audioURL))
        #expect(!InputAudioDropSupport.isAcceptedAudioFile(textURL))
        #expect(!InputAudioDropSupport.isAcceptedAudioFile(movieURL))
        #expect(!InputAudioDropSupport.isAcceptedAudioFile(directory))

        #expect(InputAudioDropSupport.validate([audioURL]) == .accepted(audioURL))
        #expect(InputAudioDropSupport.validate([textURL]) == .rejected)
        #expect(InputAudioDropSupport.validate([movieURL]) == .rejected)
        #expect(InputAudioDropSupport.validate([directory]) == .rejected)
        #expect(InputAudioDropSupport.validate([audioURL, textURL]) == .rejected)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("veloura-drop-support-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([audioURL as NSURL])
        defer { pasteboard.releaseGlobally() }

        let droppedURLs = InputAudioDropSupport.fileURLs(from: pasteboard)
        #expect(droppedURLs == [audioURL])
        #expect(InputAudioDropSupport.validate(droppedURLs) == .accepted(audioURL))
    }

    private func testSignal() -> AudioSignal {
        let sampleRate = 48_000.0
        let frameCount = 4_800
        let channel = (0..<frameCount).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / sampleRate) * 0.2)
        }
        return AudioSignal(channels: [channel, channel], sampleRate: sampleRate)
    }
}
