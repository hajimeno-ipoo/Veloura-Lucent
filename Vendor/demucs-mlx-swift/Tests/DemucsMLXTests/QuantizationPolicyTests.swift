@testable import DemucsMLX
import Testing

@Test("Local-only ignores 4-bit environment quantization")
func localOnlyIgnoresFourBitEnvironmentQuantization() {
    let configuration = DemucsModelFactory.quantizationConfiguration(
        environment: [
            "DEMUCS_QUANTIZE_BITS": "4",
            "DEMUCS_QUANTIZE_GROUP_SIZE": "32",
        ],
        modelResolutionPolicy: .localOnly
    )

    #expect(configuration == nil)
}

@Test("Local-only ignores 8-bit environment quantization")
func localOnlyIgnoresEightBitEnvironmentQuantization() {
    let configuration = DemucsModelFactory.quantizationConfiguration(
        environment: [
            "DEMUCS_QUANTIZE_BITS": "8",
            "DEMUCS_QUANTIZE_GROUP_SIZE": "128",
        ],
        modelResolutionPolicy: .localOnly
    )

    #expect(configuration == nil)
}

@Test("Compatibility policy preserves valid environment quantization")
func localThenHubPreservesValidEnvironmentQuantization() {
    let fourBit = DemucsModelFactory.quantizationConfiguration(
        environment: [
            "DEMUCS_QUANTIZE_BITS": "4",
            "DEMUCS_QUANTIZE_GROUP_SIZE": "32",
        ],
        modelResolutionPolicy: .localThenHub
    )
    let eightBit = DemucsModelFactory.quantizationConfiguration(
        environment: ["DEMUCS_QUANTIZE_BITS": "8"],
        modelResolutionPolicy: .localThenHub
    )

    #expect(fourBit == .init(bits: 4, groupSize: 32))
    #expect(eightBit == .init(bits: 8, groupSize: 64))
}

@Test("Invalid environment quantization remains disabled")
func invalidEnvironmentQuantizationRemainsDisabled() {
    for value in ["", "2", "6", "16", "invalid"] {
        let configuration = DemucsModelFactory.quantizationConfiguration(
            environment: ["DEMUCS_QUANTIZE_BITS": value],
            modelResolutionPolicy: .localThenHub
        )
        #expect(configuration == nil)
    }
}
