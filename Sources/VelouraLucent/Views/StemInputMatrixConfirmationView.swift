import SwiftUI

@MainActor
struct StemInputMatrixConfirmationView: View {
    @State private var editor: StemInputMatrixEditor

    private let onConfirm: (StemUserConfirmedMixMatrix) -> Void
    private let onCancel: () -> Void

    init(
        inputLayout: StemInputLayoutIdentity,
        now: @escaping @Sendable () -> Date = { .now },
        onConfirm: @escaping (StemUserConfirmedMixMatrix) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _editor = State(
            initialValue: StemInputMatrixEditor(
                inputLayout: inputLayout,
                now: now
            )
        )
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Header()
            LayoutSummary(inputLayout: editor.inputLayout)
            MatrixExplanation()
            MatrixGrid(rows: editor.rows)
            ValidationSummary(
                message: editor.validationSummary,
                isReady: editor.canConfirm
            )
            ActionBar(
                canConfirm: editor.canConfirm,
                onConfirm: confirm,
                onCancel: onCancel
            )
        }
        .padding(24)
        .frame(maxWidth: 760, maxHeight: 720)
        .accessibilityElement(children: .contain)
    }

    private func confirm() {
        guard let confirmation = editor.makeConfirmation() else { return }
        onConfirm(confirmation)
    }
}

private extension StemInputMatrixConfirmationView {
    struct Header: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Label("ステレオ変換を確認", systemImage: "slider.horizontal.2.square")
                    .font(.title2.bold())
                Text("入力チャンネルをLeftとRightへ送る割合を、すべて手動で指定してください。")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    struct LayoutSummary: View {
        let inputLayout: StemInputLayoutIdentity

        var body: some View {
            GroupBox("検出した入力レイアウト") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    SummaryRow(title: "入力チャンネル", value: "\(inputLayout.channelCount) ch")
                    SummaryRow(title: "レイアウト識別子", value: hexadecimal(inputLayout.layoutTag))
                    SummaryRow(title: "チャンネル構成", value: hexadecimal(inputLayout.channelBitmap))
                    SummaryRow(
                        title: "個別チャンネル情報",
                        value: "\(inputLayout.channelDescriptions.count) 件"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            }
            .accessibilityElement(children: .contain)
        }

        private func hexadecimal(_ value: UInt32) -> String {
            "0x\(String(value, radix: 16, uppercase: true))"
        }
    }

    struct SummaryRow: View {
        let title: String
        let value: String

        var body: some View {
            GridRow {
                Text(title)
                    .foregroundStyle(.secondary)
                Text(value)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
        }
    }

    struct MatrixExplanation: View {
        var body: some View {
            Label {
                Text("各係数は、その入力チャンネルをLeftまたはRightへ送る量です。値は音量と定位（左右の位置）へ直接影響します。自動設定は行いません。")
                    .font(.callout)
            } icon: {
                Image(systemName: "speaker.wave.2")
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
    }

    struct MatrixGrid: View {
        let rows: [StemInputMatrixEditor.CoefficientRow]
        @FocusState private var focusedField: Int?

        var body: some View {
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("入力")
                        Text("Left（左）")
                        Text("Right（右）")
                    }
                    .font(.headline)

                    ForEach(rows) { row in
                        CoefficientRow(
                            row: row,
                            fieldCount: rows.count * StemInputChannelMatrix.outputChannelCount,
                            focusedField: $focusedField
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("ステレオ変換係数")
            .accessibilityHint("TabキーまたはReturnキーで次の入力欄へ移動できます。")
        }
    }

    struct CoefficientRow: View {
        @Bindable var row: StemInputMatrixEditor.CoefficientRow
        let fieldCount: Int
        let focusedField: FocusState<Int?>.Binding

        var body: some View {
            GridRow {
                Text("チャンネル \(row.inputChannelIndex + 1)")
                    .font(.body)
                CoefficientField(
                    title: "入力チャンネル \(row.inputChannelIndex + 1) のLeft係数",
                    hint: "この入力を左側へ送る量を有限の数値で入力します。",
                    text: $row.leftText,
                    fieldID: leftFieldID,
                    fieldCount: fieldCount,
                    focusedField: focusedField
                )
                CoefficientField(
                    title: "入力チャンネル \(row.inputChannelIndex + 1) のRight係数",
                    hint: "この入力を右側へ送る量を有限の数値で入力します。",
                    text: $row.rightText,
                    fieldID: rightFieldID,
                    fieldCount: fieldCount,
                    focusedField: focusedField
                )
            }
        }

        private var leftFieldID: Int {
            row.inputChannelIndex * StemInputChannelMatrix.outputChannelCount
        }

        private var rightFieldID: Int {
            leftFieldID + 1
        }
    }

    struct CoefficientField: View {
        let title: String
        let hint: String
        @Binding var text: String
        let fieldID: Int
        let fieldCount: Int
        let focusedField: FocusState<Int?>.Binding

        var body: some View {
            TextField("数値", text: $text)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .focused(focusedField, equals: fieldID)
                .submitLabel(fieldID + 1 < fieldCount ? .next : .done)
                .onSubmit {
                    focusNext(after: fieldID)
                }
                .accessibilityLabel(title)
                .accessibilityHint(hint)
        }

        private func focusNext(after fieldID: Int) {
            focusedField.wrappedValue = fieldID + 1 < fieldCount ? fieldID + 1 : nil
        }
    }

    struct ValidationSummary: View {
        let message: String
        let isReady: Bool

        var body: some View {
            Label(message, systemImage: isReady ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(isReady ? Color.secondary : .orange)
                .accessibilityLabel("入力確認。\(message)")
                .accessibilityHint(
                    isReady
                        ? "確定ボタンを使用できます。"
                        : "不足または不正な入力を修正してください。"
                )
        }
    }

    struct ActionBar: View {
        let canConfirm: Bool
        let onConfirm: () -> Void
        let onCancel: () -> Void

        var body: some View {
            HStack {
                Spacer(minLength: 0)
                Button("取消", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint("行列を確定せず、入力確認を閉じます。")
                Button("確定", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirm)
                    .accessibilityHint(
                        canConfirm
                            ? "入力した係数でステレオ変換を確定します。"
                            : "すべての係数に有限の数値を入力すると使用できます。"
                    )
            }
        }
    }
}
