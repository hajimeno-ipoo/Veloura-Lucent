import Foundation
import Testing
@testable import VelouraLucent

struct StemModeSettingsTests {
    @Test
    func productionFactoryUsesApprovedMetaHTDemucsBaselineAndRequiresSeed() throws {
        let settings = StemSeparationSettings.metaHTDemucsProduction(seed: 1_234_567)

        #expect(settings.shifts == 2)
        #expect(settings.overlap == 0.25)
        #expect(settings.split)
        #expect(settings.segmentLength == .modelContract)
        #expect(settings.batchSize == 1)
        #expect(settings.seed == 1_234_567)
        #expect(try settings.validated(modelContract: makeContract()) == settings)
    }

    @Test
    func bsRoformerProductionUsesModelOwnedInferenceSettings() throws {
        let settings = StemSeparationSettings.bsRoformerSWProduction
        let profile = StemProductionModelProfile.profile(for: .bsRoformerSW)
        let contract = StemModelContract(
            separationModel: .bsRoformerSW,
            identifier: profile.modelIdentifier,
            version: profile.revision,
            assetSetIdentifier: profile.assetSetIdentifier,
            inputName: "audio",
            outputNames: Dictionary(
                uniqueKeysWithValues: StemRole.allCases.map { ($0, $0.rawValue) }
            ),
            sourceOrder: [.drums, .bass, .other, .vocals],
            sampleRate: 44_100,
            channelCount: 2,
            inputShape: [-1, 2, -1],
            outputShapes: Dictionary(
                uniqueKeysWithValues: StemRole.allCases.map { ($0, [-1, 2, -1]) }
            ),
            scalarType: .float32,
            normalization: .modelManagedIdentityBoundary,
            runtime: .mlx,
            defaultSegmentSeconds: nil,
            downloadableModelAssets: Array(profile.downloadableAssets.values),
            bundledRuntimeAssets: []
        )

        #expect(settings.model == .bsRoformerSW)
        #expect(settings.seed == nil)
        #expect(try settings.validated(modelContract: contract) == settings)
    }

    @Test
    func everySeparationFieldMustBeExplicitlyProvided() throws {
        let settings = StemSeparationSettings(
            shifts: 2,
            overlap: 0.5,
            split: true,
            segmentLength: .seconds(7.8),
            batchSize: 1,
            seed: 42
        )
        #expect(try settings.validatedParameters() == settings)
    }

    @Test
    func modelContractSegmentIsAnExplicitChoiceInsteadOfAHiddenDefault() throws {
        let settings = StemSeparationSettings(
            shifts: 0,
            overlap: 0,
            split: true,
            segmentLength: .modelContract,
            batchSize: 1,
            seed: nil
        )

        #expect(try settings.validated(modelContract: makeContract()) == settings)
        #expect(settings.segmentLength.explicitSeconds == nil)
    }

    @Test(arguments: [
        StemSeparationSettings(
            shifts: -1,
            overlap: 0.25,
            split: true,
            segmentLength: .modelContract,
            batchSize: 1,
            seed: 1
        ),
        StemSeparationSettings(
            shifts: 1,
            overlap: .infinity,
            split: true,
            segmentLength: .modelContract,
            batchSize: 1,
            seed: 1
        ),
        StemSeparationSettings(
            shifts: 1,
            overlap: 1,
            split: true,
            segmentLength: .modelContract,
            batchSize: 1,
            seed: 1
        ),
        StemSeparationSettings(
            shifts: 1,
            overlap: 0.25,
            split: true,
            segmentLength: .seconds(.nan),
            batchSize: 1,
            seed: 1
        ),
        StemSeparationSettings(
            shifts: 1,
            overlap: 0.25,
            split: true,
            segmentLength: .modelContract,
            batchSize: 0,
            seed: 1
        ),
        StemSeparationSettings(
            shifts: 1,
            overlap: 0.25,
            split: true,
            segmentLength: .modelContract,
            batchSize: 1,
            seed: nil
        )
    ])
    func invalidSeparationSettingsAreRejected(
        _ settings: StemSeparationSettings
    ) {
        #expect(throws: (any Error).self) {
            try settings.validated(modelContract: makeContract())
        }
    }

    @Test
    func unverifiedModelContractSegmentLengthIsRejected() {
        let settings = StemSeparationSettings.metaHTDemucsProduction(seed: 42)

        #expect(throws: StemSeparationSettingsError.self) {
            try settings.validated(modelContract: makeContract(segmentSeconds: 6.0))
        }
    }

    private func makeContract(segmentSeconds: Double = 7.8) -> StemModelContract {
        StemModelContract(
            separationModel: .htdemucs,
            identifier: "htdemucs",
            version: "d4519e24ddc2dd4a11d56a193092433d852c3961",
            assetSetIdentifier: "htdemucs-mlx-d4519e24",
            inputName: "batchData",
            outputNames: Dictionary(
                uniqueKeysWithValues: StemRole.allCases.map { ($0, $0.rawValue) }
            ),
            sourceOrder: [.drums, .bass, .other, .vocals],
            sampleRate: 44_100,
            channelCount: 2,
            inputShape: [-1, 2, -1],
            outputShapes: Dictionary(
                uniqueKeysWithValues: StemRole.allCases.map { ($0, [-1, 2, -1]) }
            ),
            scalarType: .float32,
            normalization: .modelManagedIdentityBoundary,
            runtime: .mlx,
            defaultSegmentSeconds: segmentSeconds,
            downloadableModelAssets: [],
            bundledRuntimeAssets: []
        )
    }
}
