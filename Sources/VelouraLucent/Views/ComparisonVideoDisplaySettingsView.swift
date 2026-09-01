import AppKit
import SwiftUI

struct ComparisonVideoDisplaySettingsView: View {
    @Bindable var model: ComparisonVideoWindowModel
    let parentWindow: NSWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            titleSettings
            roleSettings
            inspectorSettings
            fadeSettings
            visualizerSettings
            backgroundSettings
        }
    }

    private var titleSettings: some View {
        ComparisonVideoSettingsSection(title: "タイトル") {
            labeledTextField(
                title: "表示テキスト",
                text: $model.displaySettings.trackTitle
            )

            Divider()

            colorPicker(
                title: "文字の色",
                color: model.displaySettings.titleColor,
                setColor: model.setTitleColor
            )

            Divider()

            fontFamilyMenu(
                title: "フォント",
                selection: $model.displaySettings.titleFontFamily
            )

            Divider()

            fontSizeControl(value: $model.displaySettings.titleFontSize)

            Divider()

            positionControls(
                horizontal: $model.displaySettings.titlePositionX,
                vertical: $model.displaySettings.titlePositionY,
                helpText: "プレビュー内のタイトルもドラッグできます"
            )
        }
    }

    private var roleSettings: some View {
        ComparisonVideoSettingsSection(title: "役割") {
            labeledTextField(
                title: "先に再生する役割",
                text: $model.displaySettings.firstRoleTitle
            )

            colorPicker(
                title: "先に再生する文字の色",
                color: model.displaySettings.firstRoleColor,
                setColor: model.setFirstRoleColor
            )

            Divider()

            labeledTextField(
                title: "次に再生する役割",
                text: $model.displaySettings.secondRoleTitle
            )

            colorPicker(
                title: "次に再生する文字の色",
                color: model.displaySettings.secondRoleColor,
                setColor: model.setSecondRoleColor
            )

            Divider()

            fontFamilyMenu(
                title: "フォント",
                selection: $model.displaySettings.roleFontFamily
            )

            Divider()

            fontSizeControl(value: $model.displaySettings.roleFontSize)

            Divider()

            positionControls(
                horizontal: $model.displaySettings.rolePositionX,
                vertical: $model.displaySettings.rolePositionY,
                helpText: "プレビュー内の役割もドラッグできます"
            )
        }
    }

    private var inspectorSettings: some View {
        ComparisonVideoSettingsSection(title: "情報表示") {
            inspectorSizeControls

            Divider()

            positionControls(
                horizontal: $model.displaySettings.inspectorPositionX,
                vertical: $model.displaySettings.inspectorPositionY,
                helpText: "プレビュー内をドラッグして位置を変更できます"
            )
        }
    }

    private var inspectorSizeControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("比率")
                    .font(.title3)

                inspectorAspectRatioMenu

                if model.displaySettings.inspectorAspectRatio == .custom {
                    HStack(spacing: 10) {
                        customAspectField(
                            title: "幅",
                            value: Binding(
                                get: { model.displaySettings.customAspectWidth },
                                set: { model.setCustomInspectorAspectWidth($0) }
                            )
                        )

                        Text(":")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        customAspectField(
                            title: "高さ",
                            value: Binding(
                                get: { model.displaySettings.customAspectHeight },
                                set: { model.setCustomInspectorAspectHeight($0) }
                            )
                        )
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text("大きさ")
                        .font(.title3)

                    Spacer(minLength: 12)

                    Text(inspectorSizeText)
                        .font(.title3)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { model.inspectorScale },
                        set: { model.setInspectorScale($0) }
                    ),
                    in: model.inspectorScaleRange,
                    step: 1
                )
                .tint(LiquidGlassSegmentedPickerStyle.sliderTint)
                .accessibilityLabel("情報表示の大きさ")
                .accessibilityValue(inspectorSizeText)
            }
        }
        .padding(.vertical, 12)
    }

    private var inspectorAspectRatioMenu: some View {
        Menu {
            ForEach(ComparisonVideoInspectorAspectRatio.allCases) { aspectRatio in
                Button {
                    model.setInspectorAspectRatio(aspectRatio)
                } label: {
                    if aspectRatio == model.displaySettings.inspectorAspectRatio {
                        Label(aspectRatio.title, systemImage: "checkmark")
                    } else {
                        Text(aspectRatio.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text("情報表示の比率")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(model.displaySettings.inspectorAspectRatio.title)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .accessibilityHidden(true)
            }
            .font(.title3)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .velouraAdaptiveGlass(in: .rect(cornerRadius: 10), interactive: true)
            .contentShape(.rect(cornerRadius: 10))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("情報表示の比率")
        .accessibilityValue(model.displaySettings.inspectorAspectRatio.title)
    }

    private var inspectorSizeText: String {
        let size = model.inspectorSize
        return "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) pt"
    }

    private var fadeSettings: some View {
        ComparisonVideoSettingsSection(title: "フェード") {
            fadeToggleRow(
                title: "映像",
                fadeInEnabled: Binding(
                    get: { model.displaySettings.videoFadeInEnabled },
                    set: { model.setVideoFadeInEnabled($0) }
                ),
                fadeOutEnabled: Binding(
                    get: { model.displaySettings.videoFadeOutEnabled },
                    set: { model.setVideoFadeOutEnabled($0) }
                )
            )

            Divider()

            fadeToggleRow(
                title: "曲",
                fadeInEnabled: Binding(
                    get: { model.displaySettings.audioFadeInEnabled },
                    set: { model.setAudioFadeInEnabled($0) }
                ),
                fadeOutEnabled: Binding(
                    get: { model.displaySettings.audioFadeOutEnabled },
                    set: { model.setAudioFadeOutEnabled($0) }
                )
            )

            Divider()

            fadeDurationControl(
                title: "フェードイン",
                value: Binding(
                    get: { model.displaySettings.fadeInDuration },
                    set: { model.setFadeInDuration($0) }
                )
            )

            Divider()

            fadeDurationControl(
                title: "フェードアウト",
                value: Binding(
                    get: { model.displaySettings.fadeOutDuration },
                    set: { model.setFadeOutDuration($0) }
                )
            )
        }
    }

    private var visualizerSettings: some View {
        ComparisonVideoSettingsSection(title: "オーディオビジュアライザー") {
            Toggle("表示する", isOn: $model.displaySettings.visualizerEnabled)
                .font(.title3)
                .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Text("配色")
                    .font(.title3.weight(.semibold))
                    .padding(.top, 12)

                LiquidGlassSegmentedPicker(
                    title: "ビジュアライザーの配色",
                    options: ComparisonVideoVisualizerPaletteMode.allCases,
                    selection: $model.displaySettings.visualizerPaletteMode,
                    label: \ComparisonVideoVisualizerPaletteMode.title,
                    maxWidth: .infinity,
                    labelFont: .title3,
                    optionMinHeight: 38
                )
                .padding(.vertical, 12)

                if model.displaySettings.visualizerPaletteMode == .custom {
                    Divider()

                    Text("3色グラデーション")
                        .font(.title3.weight(.semibold))
                        .padding(.top, 12)

                    colorPicker(
                        title: "左の色",
                        color: model.displaySettings.visualizerLeadingColor,
                        setColor: model.setVisualizerLeadingColor
                    )

                    Divider()

                    colorPicker(
                        title: "中央の色",
                        color: model.displaySettings.visualizerCenterColor,
                        setColor: model.setVisualizerCenterColor
                    )

                    Divider()

                    colorPicker(
                        title: "右の色",
                        color: model.displaySettings.visualizerTrailingColor,
                        setColor: model.setVisualizerTrailingColor
                    )
                }
            }

            Divider()

            visualizerBehaviorControl(
                title: "反応速度",
                value: Binding(
                    get: { model.displaySettings.visualizerResponse },
                    set: { model.setVisualizerResponse($0) }
                ),
                range: 0...99,
                helpText: "値が変化する滑らかさです。高いほど滑らかに動きます。"
            )

            Divider()

            visualizerBehaviorControl(
                title: "高さスケール",
                value: $model.displaySettings.visualizerHeightScale,
                range: 25...300,
                helpText: "音量に対するドットの高さを調整します。"
            )

            Divider()

            visualizerDimensionControl(
                title: "横幅",
                value: $model.displaySettings.visualizerWidth
            )

            Divider()

            visualizerDimensionControl(
                title: "高さ",
                value: $model.displaySettings.visualizerHeight
            )

            Divider()

            visualizerScaleControl(
                value: $model.displaySettings.visualizerScale
            )

            Divider()

            positionControls(
                horizontal: $model.displaySettings.visualizerPositionX,
                vertical: $model.displaySettings.visualizerPositionY,
                helpText: "プレビュー内のビジュアライザーもドラッグできます"
            )
        }
    }

    private func fadeToggleRow(
        title: String,
        fadeInEnabled: Binding<Bool>,
        fadeOutEnabled: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))

            HStack(spacing: 24) {
                Toggle("フェードイン", isOn: fadeInEnabled)
                Toggle("フェードアウト", isOn: fadeOutEnabled)
            }
            .font(.title3)
        }
        .padding(.vertical, 12)
    }

    private func fadeDurationControl(
        title: String,
        value: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.title3)

                Spacer(minLength: 12)

                TextField(
                    title,
                    value: value,
                    format: .number.precision(.fractionLength(1))
                )
                .font(.title3)
                .multilineTextAlignment(.trailing)
                .modifier(ComparisonVideoInputFieldModifier(width: 76))

                Text("秒")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Stepper(
                    "\(title)を微調整",
                    value: value,
                    in: ComparisonVideoDisplaySettings.fadeDurationRange,
                    step: 0.1
                )
                .labelsHidden()
                .fixedSize()
            }

            Slider(
                value: value,
                in: ComparisonVideoDisplaySettings.fadeDurationRange,
                step: 0.1
            )
            .tint(LiquidGlassSegmentedPickerStyle.sliderTint)
            .accessibilityLabel(title)
            .accessibilityValue("\(value.wrappedValue.formatted(.number.precision(.fractionLength(1))))秒")
        }
        .padding(.vertical, 12)
    }

    private func visualizerDimensionControl(
        title: String,
        value: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.title3)

                Spacer(minLength: 12)

                TextField(
                    title,
                    value: value,
                    format: .number.precision(.fractionLength(2))
                )
                .font(.title3)
                .multilineTextAlignment(.trailing)
                .modifier(ComparisonVideoInputFieldModifier(width: 76))

                Stepper(
                    "\(title)を微調整",
                    value: value,
                    in: ComparisonVideoDisplaySettings.visualizerDimensionRange,
                    step: 0.01
                )
                .labelsHidden()
                .fixedSize()
            }

            Slider(
                value: value,
                in: ComparisonVideoDisplaySettings.visualizerDimensionRange,
                step: 0.01
            )
            .tint(LiquidGlassSegmentedPickerStyle.sliderTint)
            .accessibilityLabel("ビジュアライザーの\(title)")
            .accessibilityValue(
                value.wrappedValue.formatted(
                    .number.precision(.fractionLength(2))
                )
            )
        }
        .padding(.vertical, 12)
    }

    private var backgroundSettings: some View {
        ComparisonVideoSettingsSection(title: "背景") {
            colorPicker(
                title: "背景色",
                color: model.displaySettings.backgroundColor,
                setColor: model.setBackgroundColor
            )

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button("背景画像を選ぶ", systemImage: "photo") {
                        FilePanelService.chooseImageFile(attachedTo: parentWindow) { fileURL in
                            guard let fileURL else { return }
                            model.setBackgroundImage(from: fileURL)
                        }
                    }
                    .font(.title3)
                    .controlSize(.large)

                    if let backgroundImage = model.displaySettings.backgroundImage {
                        Text(backgroundImage.fileName)
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("解除") {
                            model.clearBackgroundImage()
                        }
                        .font(.title3)
                    }
                }

                if model.displaySettings.backgroundImage != nil {
                    LiquidGlassSegmentedPicker(
                        title: "背景画像の表示方法",
                        options: ComparisonVideoBackgroundImageLayout.allCases,
                        selection: $model.displaySettings.backgroundImageLayout,
                        label: \ComparisonVideoBackgroundImageLayout.title,
                        maxWidth: .infinity,
                        labelFont: .title3,
                        optionMinHeight: 38
                    )
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func visualizerScaleControl(
        value: Binding<Double>
    ) -> some View {
        let percentage = Binding(
            get: { value.wrappedValue * 100 },
            set: { value.wrappedValue = $0 / 100 }
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("拡大率")
                    .font(.title3)

                Spacer(minLength: 12)

                TextField(
                    "拡大率",
                    value: percentage,
                    format: .number.precision(.fractionLength(0))
                )
                .font(.title3)
                .multilineTextAlignment(.trailing)
                .modifier(ComparisonVideoInputFieldModifier(width: 76))

                Text("%")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Stepper(
                    "拡大率を微調整",
                    value: percentage,
                    in: 25...200,
                    step: 1
                )
                .labelsHidden()
                .fixedSize()
            }

            Slider(
                value: percentage,
                in: 25...200,
                step: 1
            )
            .tint(LiquidGlassSegmentedPickerStyle.sliderTint)
            .accessibilityLabel("ビジュアライザーの拡大率")
            .accessibilityValue("\(Int(percentage.wrappedValue.rounded()))%")
        }
    }

    private func visualizerBehaviorControl(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        helpText: String
    ) -> some View {
        let percentage = Binding(
            get: { value.wrappedValue * 100 },
            set: { value.wrappedValue = $0 / 100 }
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.title3)

                Spacer(minLength: 12)

                TextField(
                    title,
                    value: percentage,
                    format: .number.precision(.fractionLength(0))
                )
                .font(.title3)
                .multilineTextAlignment(.trailing)
                .modifier(ComparisonVideoInputFieldModifier(width: 76))

                Text("%")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Stepper(
                    "\(title)を微調整",
                    value: percentage,
                    in: range,
                    step: 1
                )
                .labelsHidden()
                .fixedSize()
            }

            Slider(
                value: percentage,
                in: range,
                step: 1
            )
            .tint(LiquidGlassSegmentedPickerStyle.sliderTint)
            .accessibilityLabel("ビジュアライザーの\(title)")
            .accessibilityValue("\(Int(percentage.wrappedValue.rounded()))%")

            Text(helpText)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func labeledTextField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.title3)
            TextField(title, text: text)
                .font(.title3)
                .controlSize(.large)
                .modifier(ComparisonVideoInputFieldModifier())
        }
        .padding(.vertical, 12)
    }

    private func colorPicker(
        title: String,
        color: ComparisonVideoRGBAColor,
        setColor: @escaping (NSColor) -> Void
    ) -> some View {
        ColorPicker(
            title,
            selection: Binding(
                get: { swiftUIColor(color) },
                set: { setColor(NSColor($0)) }
            ),
            supportsOpacity: false
        )
        .font(.title3)
        .padding(.vertical, 12)
    }

    private func fontFamilyMenu(
        title: String,
        selection: Binding<String?>
    ) -> some View {
        Menu {
            Button {
                selection.wrappedValue = nil
            } label: {
                if selection.wrappedValue == nil {
                    Label("システム", systemImage: "checkmark")
                } else {
                    Text("システム")
                }
            }

            Divider()

            ForEach(Self.availableFontFamilies, id: \.self) { family in
                Button {
                    selection.wrappedValue = family
                } label: {
                    if selection.wrappedValue == family {
                        Label(family, systemImage: "checkmark")
                    } else {
                        Text(family)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(selection.wrappedValue ?? "システム")
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .accessibilityHidden(true)
            }
            .font(.title3)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .velouraAdaptiveGlass(in: .rect(cornerRadius: 10), interactive: true)
            .contentShape(.rect(cornerRadius: 10))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .padding(.vertical, 12)
        .accessibilityLabel(title)
        .accessibilityValue(selection.wrappedValue ?? "システム")
    }

    private static let availableFontFamilies = NSFontManager.shared.availableFontFamilies.sorted {
        $0.localizedStandardCompare($1) == .orderedAscending
    }

    private func fontSizeControl(value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("フォントサイズ")
                    .font(.title3)

                Spacer(minLength: 12)

                TextField(
                    "フォントサイズ",
                    value: value,
                    format: .number.precision(.fractionLength(0))
                )
                .font(.title3)
                .multilineTextAlignment(.trailing)
                .modifier(ComparisonVideoInputFieldModifier(width: 72))

                Text("pt")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: 24...300, step: 1)
                .tint(LiquidGlassSegmentedPickerStyle.sliderTint)
                .accessibilityLabel("フォントサイズ")
                .accessibilityValue("\(Int(value.wrappedValue))ポイント")
        }
        .padding(.vertical, 12)
    }

    private func positionControls(
        horizontal: Binding<Double>,
        vertical: Binding<Double>,
        helpText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            positionAxisControl(title: "水平位置", value: horizontal)
            positionAxisControl(title: "垂直位置", value: vertical)

            Text(helpText)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }

    private func positionAxisControl(title: String, value: Binding<Double>) -> some View {
        let normalizedValue = normalizedPositionBinding(value)

        return HStack(spacing: 10) {
            Text(title)
                .font(.title3)
                .frame(width: 76, alignment: .leading)

            Slider(value: normalizedValue, in: 0...1, step: 0.01)
                .tint(LiquidGlassSegmentedPickerStyle.sliderTint)
                .accessibilityLabel(title)
                .accessibilityValue(normalizedPositionText(normalizedValue.wrappedValue))

            TextField(
                title,
                value: normalizedValue,
                format: .number.precision(.fractionLength(2))
            )
            .font(.title3)
            .multilineTextAlignment(.trailing)
            .modifier(ComparisonVideoInputFieldModifier(width: 76))

            Stepper(
                "\(title)を微調整",
                value: normalizedValue,
                in: 0...1,
                step: 0.01
            )
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("\(title)を微調整")
            .accessibilityValue(normalizedPositionText(normalizedValue.wrappedValue))
        }
    }

    private func normalizedPositionBinding(_ value: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { value.wrappedValue / 100 },
            set: { value.wrappedValue = min(max($0, 0), 1) * 100 }
        )
    }

    private func normalizedPositionText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    private func customAspectField(title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.title3)
            TextField(
                title,
                value: value,
                format: .number.precision(.fractionLength(0...2))
            )
            .font(.title3)
            .multilineTextAlignment(.trailing)
            .modifier(ComparisonVideoInputFieldModifier(width: 82))
        }
    }

    private func swiftUIColor(_ color: ComparisonVideoRGBAColor) -> Color {
        Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}

private struct ComparisonVideoInputFieldModifier: ViewModifier {
    var width: CGFloat?

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .frame(width: width)
            .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.32), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

struct ComparisonVideoSettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.secondary.opacity(0.36), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }
}
