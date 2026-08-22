import Foundation
import Testing
@testable import BSRoformerMLX

@Test
func loadsOfficialConfiguration() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let configuration = try BSRoformerConfiguration.load(
        from: packageRoot.appendingPathComponent("Config/BS-Roformer-SW.json")
    )

    #expect(configuration.frequencyBinCount == 1025)
    #expect(configuration.frequenciesPerBand.count == 62)
    #expect(configuration.chunkSampleCount == 409_600)
    #expect(configuration.chunkSampleCount(for: 300_032) == 130_560)
    #expect(configuration.stepSampleCount(for: configuration.chunkSampleCount) == 352_800)
    #expect(configuration.stemNames == ["bass", "drums", "other", "vocals", "guitar", "piano"])
}

@Test
func officialConfigurationRequiresExactly1915Weights() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let configuration = try BSRoformerConfiguration.load(
        from: packageRoot.appendingPathComponent("Config/BS-Roformer-SW.json")
    )

    #expect(BSRoformerModel.requiredWeightKeys(configuration: configuration).count == 1_915)
}

@Test
func mapsPublishedStemTapWeightNamesToRuntimeNames() {
    #expect(
        BSRoformerModel.normalizedPublishedWeightKey("band_split.to_features.0.0.gamma")
            == "band_split.to_features_0.norm.weight"
    )
    #expect(
        BSRoformerModel.normalizedPublishedWeightKey("layers.0.0.layers.0.0.to_out.0.weight")
            == "layers_0.time_transformer.layers_0.attn.to_out.layers.0.weight"
    )
    #expect(
        BSRoformerModel.normalizedPublishedWeightKey("layers.11.1.layers.0.1.net.4.bias")
            == "layers_11.freq_transformer.layers_0.ff.net.layers.4.bias"
    )
    #expect(
        BSRoformerModel.normalizedPublishedWeightKey("mask_estimators.5.to_freqs.61.0.2.weight")
            == "mask_estimators_5.to_freqs_61.layers.2.weight"
    )
    #expect(
        BSRoformerModel.normalizedPublishedWeightKey("final_norm.gamma")
            == "final_norm.weight"
    )
}
