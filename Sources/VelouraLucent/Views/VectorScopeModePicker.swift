import SwiftUI

struct VectorScopeModePicker: View {
    @Binding var displayMode: VectorScopeDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("ベクトルスコープ表示")
                    .font(.callout.weight(.semibold))
                TermHelpButton(
                    title: "ベクトルスコープ表示",
                    reading: "べくとるすこーぷひょうじ",
                    description: "Polar Sampleは、左右チャンネルのサンプルを半円上の点で表示します。45度安全ライン内は同相、外側は位相ずれの目安です。Polar Levelは、短い時間のレベルを線で表示します。線の角度で左右位置、長さで選択中の検出方式のレベルを見ます。Lissajousは、左右チャンネルの瞬間的な関係を菱形の中の点で表示します。縦に近いほど同相、横に広がるほど逆相成分が多い状態です。"
                )
            }

            LiquidGlassSegmentedPicker(
                title: "ベクトルスコープ表示",
                options: VectorScopeDisplayMode.allCases,
                selection: $displayMode,
                label: \.title
            )
        }
    }
}
