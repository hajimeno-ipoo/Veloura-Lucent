import Foundation
import Testing
@testable import VelouraLucent

@MainActor
struct StemModeCorrectionSettingsViewTests {
    @Test
    func sharedCatalogContainsAllTwelveStandardControlsWithTheSameRange() {
        let definitions = CorrectionSettingControlCatalog.all

        #expect(definitions.map(\.id) == CorrectionSettingControlID.allCases)
        #expect(definitions.count == 12)
        #expect(definitions.allSatisfy { $0.range == (0 ... 1) })
        #expect(definitions.allSatisfy { $0.step == 0.01 })
        #expect(definitions.allSatisfy { $0.labels.count == 3 })
        #expect(definitions.allSatisfy { !$0.help.description.isEmpty })
        #expect(Set(definitions.map(\.title)).count == 12)
    }

    @Test
    func stemInspectorSelectsOneRoleAndUsesStandardKnobsForRoleSpecificSettings() throws {
        let correctionView = try source(
            "Sources/VelouraLucent/Views/StemModeCorrectionSettingsView.swift"
        )
        let controlList = try source(
            "Sources/VelouraLucent/Views/StemModeCorrectionControlList.swift"
        )
        let mastering = try source(
            "Sources/VelouraLucent/Views/StemModeMasteringSettingsView.swift"
        )
        let inspector = try source(
            "Sources/VelouraLucent/Views/StemModeInspectorView.swift"
        )
        let standard = try source(
            "Sources/VelouraLucent/Views/InspectorSettingsPanel.swift"
        )

        #expect(correctionView.contains("Stem別の独立設定"))
        #expect(correctionView.contains("設定するStem"))
        #expect(correctionView.contains("選択中Stemの処理量上限"))
        #expect(correctionView.contains("設定値より強くしません"))
        #expect(correctionView.contains("選択中Stemの補正上限を決める出発点です"))
        #expect(correctionView.contains("StemRole.allCases"))
        #expect(correctionView.contains("layout: .basic"))
        #expect(correctionView.contains("layout: .repair"))
        #expect(correctionView.contains("layout: .advanced"))
        #expect(controlList.contains("model.isCorrectionSettingsDisabled"))
        #expect(controlList.contains("try model.updateCorrectionSettings"))
        #expect(controlList.contains("DAWKnobControl("))
        #expect(controlList.contains("ViewThatFits(in: .horizontal)"))
        #expect(controlList.contains("DAWKnobMetrics.threeColumnWidth"))
        #expect(controlList.contains("DAWKnobMetrics.twoColumnWidth"))
        #expect(controlList.contains("DAWKnobMetrics.controlWidth"))
        #expect(!controlList.contains("StemModeSettingSlider("))
        #expect(inspector.contains("StemModeCorrectionSettingsView(model: model)"))

        #expect(mastering.contains("SettingsDisclosureCard("))
        #expect(mastering.contains("DAWKnobControl("))
        #expect(mastering.contains("initiallyExpanded: true"))
        #expect(mastering.contains("model.selectedMasteringProfile.presetTargetText"))
        #expect(mastering.contains("LiquidGlassActionButton("))
        #expect(!mastering.contains("StemModeSettingSlider("))
        #expect(!mastering.contains("DisclosureGroup("))
        #expect(!mastering.contains(".disabled(model.isMasteringSettingsDisabled)"))
        #expect(inspector.contains(
            "StemModeMasteringSettingsView(model: model)\n                    .disabled(model.isMasteringSettingsDisabled)"
        ))

        for identifier in CorrectionSettingControlID.allCases {
            #expect(standard.contains(identifier.rawValue))
        }
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appending(path: relativePath),
            encoding: .utf8
        )
    }
}
