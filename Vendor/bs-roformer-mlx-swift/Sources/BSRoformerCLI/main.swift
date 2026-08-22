import BSRoformerMLX
import Foundation

@main
enum BSRoformerCLI {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 4 else {
            FileHandle.standardError.write(Data(
                """
                使用方法:
                  bs-roformer-mlx-swift <weights.safetensors> <config.json> <input.wav> <output-directory>

                """.utf8
            ))
            throw Exit.invalidArguments
        }

        let weightsURL = URL(fileURLWithPath: arguments[0])
        let configurationURL = URL(fileURLWithPath: arguments[1])
        let inputURL = URL(fileURLWithPath: arguments[2])
        let outputDirectory = URL(fileURLWithPath: arguments[3], isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let separator = try BSRoformerSeparator(
            weightsURL: weightsURL,
            configurationURL: configurationURL
        )
        let audio = try BSRoformerAudioIO.load(
            from: inputURL,
            targetSampleRate: separator.model.configuration.sampleRate,
            targetChannels: separator.model.configuration.channels
        )
        let result = try separator.separate(audio) { completed, total in
            print("chunk \(completed)/\(total)")
        }
        for stem in BSRoformerStem.allCases {
            guard let stemAudio = result.stems[stem] else { continue }
            try BSRoformerAudioIO.writeFloatWAV(
                stemAudio,
                to: outputDirectory.appendingPathComponent("\(stem.rawValue).wav")
            )
        }
    }

    enum Exit: Error {
        case invalidArguments
    }
}
