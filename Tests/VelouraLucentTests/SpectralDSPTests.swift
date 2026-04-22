import Foundation
import Testing
@testable import VelouraLucent

struct SpectralDSPTests {
    @Test
    func smallWindowMedianMatchesReferenceImplementation() {
        let values = (0..<64).map { index in
            Float(sin(Double(index) * 0.47) * 0.6 + cos(Double(index) * 0.19) * 0.3)
        }

        for windowSize in [5, 7, 9, 17] {
            let optimized = SpectralDSP.medianFilter(values, windowSize: windowSize)
            let reference = referenceMedianFilter(values, windowSize: windowSize)
            #expect(optimized == reference)
        }
    }

    private func referenceMedianFilter(_ values: [Float], windowSize: Int) -> [Float] {
        guard windowSize > 1, !values.isEmpty else { return values }
        let radius = windowSize / 2
        return values.indices.map { index in
            let lower = max(0, index - radius)
            let upper = min(values.count - 1, index + radius)
            return Array(values[lower...upper]).sorted()[((upper - lower) / 2)]
        }
    }
}
