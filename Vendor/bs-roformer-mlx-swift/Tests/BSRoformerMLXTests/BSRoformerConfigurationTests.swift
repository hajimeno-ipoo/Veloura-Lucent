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
