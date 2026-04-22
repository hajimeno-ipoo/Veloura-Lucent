import Foundation

#if canImport(Metal)
import Metal
#endif

struct MetalAudioAnalysisProcessor: Sendable {
    var isAvailable: Bool {
        #if canImport(Metal)
        MTLCreateSystemDefaultDevice() != nil
        #else
        false
        #endif
    }

    func separatedMeanSpectra(spectrogram: Spectrogram) -> AudioSeparatedMeanSpectra? {
        guard isAvailable else { return nil }
        return nil
    }
}
