import SwiftUI

struct ProcessingModeToolbarPicker: View {
    @Binding var selection: ProcessingMode
    let isDisabled: Bool

    var body: some View {
        LiquidGlassSegmentedPicker(
            title: "処理モード",
            options: ProcessingMode.allCases,
            selection: $selection,
            label: \.title,
            maxWidth: 280,
            labelFont: .body,
            optionMinHeight: 36,
            isDisabled: isDisabled
        )
        .frame(width: 280)
        .accessibilityLabel(AppLanguageSettings.string("処理モード"))
        .accessibilityHint(AppLanguageSettings.string(
            isDisabled
                ? "現在の処理が完了してから切り替えられます"
                : "スタンダードとステムを切り替えます"
        ))
    }
}
