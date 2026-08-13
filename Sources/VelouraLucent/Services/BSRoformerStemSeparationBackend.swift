import BSRoformerMLX
import Foundation

enum BSRoformerStemSeparationBackendError: LocalizedError, Equatable, Sendable {
    case missingStem(String)

    var errorDescription: String? {
        switch self {
        case .missingStem(let name):
            "BS-RoFormer分離結果に\(name)がありません。"
        }
    }
}

enum BSRoformerStemOutputMapper {
    static func makeSixStemOutput(
        from separation: BSRoformerSeparation
    ) throws -> StemSeparationBackendOutput {
        func required(_ stem: BSRoformerStem) throws -> BSRoformerAudio {
            guard let audio = separation.stems[stem] else {
                throw BSRoformerStemSeparationBackendError.missingStem(stem.rawValue)
            }
            return audio
        }

        let bass = try required(.bass)
        let drums = try required(.drums)
        let other = try required(.other)
        let vocals = try required(.vocals)
        let guitar = try required(.guitar)
        let piano = try required(.piano)

        return StemSeparationBackendOutput(stems: [
            StemRole.bass.rawValue: pcm(from: bass),
            StemRole.drums.rawValue: pcm(from: drums),
            StemRole.other.rawValue: pcm(from: other),
            StemRole.vocals.rawValue: pcm(from: vocals),
            StemRole.guitar.rawValue: pcm(from: guitar),
            StemRole.piano.rawValue: pcm(from: piano),
        ])
    }

    private static func pcm(from audio: BSRoformerAudio) -> StemSeparationPCM {
        StemSeparationPCM(
            channelMajorSamples: audio.channelMajorSamples,
            channelCount: audio.channels,
            sampleRate: audio.sampleRate
        )
    }
}

struct BSRoformerStemSeparationBackendFactory: StemSeparationBackendCreating {
    func makeBackend(
        configuration: StemSeparationBackendConfiguration
    ) async throws -> any StemSeparationBackend {
        try await Task.detached(priority: .userInitiated) {
            let separator = try BSRoformerSeparator(
                weightsURL: configuration.modelWeightsURL,
                configurationURL: configuration.modelConfigurationURL
            )
            return BSRoformerStemSeparationBackend(separator: separator)
        }.value
    }
}

private final class BSRoformerStemSeparationBackend: StemSeparationBackend, @unchecked Sendable {
    private let separator: BSRoformerSeparator

    init(separator: BSRoformerSeparator) {
        self.separator = separator
    }

    func separate(
        input: StemSeparationPCM,
        cancellationToken: StemSeparationCancellationToken,
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws -> StemSeparationBackendOutput {
        let audio = try BSRoformerAudio(
            channelMajorSamples: input.channelMajorSamples,
            channels: input.channelCount,
            sampleRate: input.sampleRate
        )
        do {
            return try await Task.detached(priority: .userInitiated) { [self] in
                let separation = try separator.separate(
                    audio,
                    progress: { completed, total in
                        let fraction = total > 0 ? Double(completed) / Double(total) : 0
                        progressHandler(
                            min(max(fraction, 0), 1),
                            "BS-RoFormer \(completed)/\(total)"
                        )
                    },
                    isCancelled: {
                        cancellationToken.isCancelled
                    }
                )
                return try BSRoformerStemOutputMapper.makeSixStemOutput(from: separation)
            }.value
        } catch BSRoformerError.cancelled {
            throw CancellationError()
        }
    }
}
