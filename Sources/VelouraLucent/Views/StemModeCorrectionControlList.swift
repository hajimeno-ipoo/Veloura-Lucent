import SwiftUI

@MainActor
struct StemModeCorrectionControlList: View {
    enum Layout {
        case basic
        case repair
        case advanced

        var definitions: [CorrectionSettingControlDefinition] {
            switch self {
            case .basic:
                CorrectionSettingControlCatalog.basic
            case .repair:
                CorrectionSettingControlCatalog.repair
            case .advanced:
                CorrectionSettingControlCatalog.advanced
            }
        }
    }

    @Bindable var model: StemModeWorkspaceModel
    let layout: Layout

    var body: some View {
        Group {
            switch layout {
            case .basic:
                basicKnobRow
            case .repair:
                repairKnobRow
            case .advanced:
                advancedKnobRow
            }
        }
        .disabled(model.isCorrectionSettingsDisabled)
    }

    private var basicKnobRow: some View {
        DAWResponsiveThreeControlLayout {
            ForEach(layout.definitions, id: \.id) { definition in
                knob(for: definition)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var repairKnobRow: some View {
        VStack(spacing: DAWKnobMetrics.rowSpacing) {
            knobRow(
                Array(layout.definitions.prefix(3)),
                width: DAWKnobMetrics.threeColumnWidth
            )
            knobRow(
                Array(layout.definitions.dropFirst(3)),
                width: DAWKnobMetrics.twoColumnWidth
            )
        }
        .frame(width: DAWKnobMetrics.threeColumnWidth, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var advancedKnobRow: some View {
        VStack(spacing: DAWKnobMetrics.rowSpacing) {
            knobRow(
                Array(layout.definitions.prefix(2)),
                width: DAWKnobMetrics.twoColumnWidth
            )
            knobRow(
                Array(layout.definitions.dropFirst(2)),
                width: DAWKnobMetrics.twoColumnWidth
            )
        }
        .frame(width: DAWKnobMetrics.twoColumnWidth, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func knobRow(
        _ definitions: [CorrectionSettingControlDefinition],
        width: CGFloat
    ) -> some View {
        HStack(alignment: .top, spacing: DAWKnobMetrics.columnSpacing) {
            ForEach(definitions, id: \.id) { definition in
                knob(for: definition)
            }
        }
        .frame(width: width)
    }

    private func knob(
        for definition: CorrectionSettingControlDefinition
    ) -> some View {
        let value = model.selectedRoleCorrectionSettings[keyPath: definition.keyPath]
        return DAWKnobControl(
            title: definition.title,
            help: definition.help,
            valueText: percentText(value),
            displayValueText: percentNumberText(value),
            unitText: "%",
            labels: definition.labels,
            value: correctionBinding(for: definition),
            range: definition.range,
            step: definition.step
        )
    }

    private func correctionBinding(
        for definition: CorrectionSettingControlDefinition
    ) -> Binding<Float> {
        Binding(
            get: { model.selectedRoleCorrectionSettings[keyPath: definition.keyPath] },
            set: { newValue in
                do {
                    try model.updateCorrectionSettings { settings in
                        settings[keyPath: definition.keyPath] = min(
                            max(newValue, definition.range.lowerBound),
                            definition.range.upperBound
                        )
                    }
                } catch {
                    model.presentControllerFailure(
                        title: "Stem補正設定を変更できません",
                        message: error.localizedDescription
                    )
                }
            }
        )
    }

    private func percentText(_ value: Float) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private func percentNumberText(_ value: Float) -> String {
        String(format: "%.0f", value * 100)
    }
}
