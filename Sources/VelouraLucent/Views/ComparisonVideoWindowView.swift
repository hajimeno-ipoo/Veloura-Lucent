import AppKit
import SwiftUI

struct ComparisonVideoWindowView: View {
    let launchStore: ComparisonVideoLaunchStore
    @State private var model = ComparisonVideoWindowModel()
    @State private var isWindowFullScreen = false
    @AppStorage(AppAppearanceSettings.windowBackgroundMaterialAmountKey)
    private var windowBackgroundMaterialAmount =
        AppAppearanceSettings.defaultWindowBackgroundMaterialAmount
    @AppStorage(AppAppearanceSettings.windowBackgroundBlurEnabledKey)
    private var isWindowBackgroundBlurEnabled =
        AppAppearanceSettings.defaultWindowBackgroundBlurEnabled
    @AppStorage(AppAppearanceSettings.windowBackgroundBlurLevelKey)
    private var windowBackgroundBlurLevel =
        AppAppearanceSettings.defaultWindowBackgroundBlurLevel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        @Bindable var model = model
        let appearanceState = AppAppearanceSettings.windowAppearanceState(
            materialAmount: windowBackgroundMaterialAmount,
            isBlurEnabled: isWindowBackgroundBlurEnabled,
            blurLevel: windowBackgroundBlurLevel,
            isFullScreen: isWindowFullScreen,
            reduceTransparency: reduceTransparency
        )

        HSplitView {
            VStack(spacing: 0) {
                WorkspaceFixedHeaderView(
                    title: "比較動画",
                    summary: "60秒の範囲を選び、15秒ごとに音源を切り替えます。"
                ) {
                    EmptyView()
                }

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        sourceSelection(model: model)
                        rangeSelection(model: model)
                        exportSettings(model: model)
                        if let message = model.message {
                            Text(message)
                                .font(.body)
                                .foregroundStyle(
                                    message == "動画を書き出しました。" ? .green : .secondary
                                )
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
            .frame(minWidth: 390, idealWidth: 430, maxWidth: 520)

            ComparisonVideoPlayerView(model: model)
                .frame(minWidth: 520)
        }
        .environment(\.velouraIsFullScreen, isWindowFullScreen)
        .frame(minWidth: 980, minHeight: 700)
        .velouraWindowBackground(state: appearanceState)
        .background(
            WindowChromeConfigurator(
                minSize: NSSize(width: 980, height: 700),
                appearanceState: appearanceState,
                isFullScreen: $isWindowFullScreen
            )
        )
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    if model.isExporting {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button("動画を書き出す", systemImage: "square.and.arrow.up") {
                        chooseExportDestination(model: model)
                    }
                    .disabled(!model.canExport)
                }
            }
        }
        .task(id: launchStore.revision) {
            model.configure(with: launchStore.launch)
        }
        .onDisappear {
            model.close()
        }
    }

    private func sourceSelection(model: ComparisonVideoWindowModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("比較する音源")
                .font(.title3.bold())

            GlassEffectContainer(spacing: 8) {
                VStack(spacing: 8) {
                    sourceMenu(
                        title: "先に再生",
                        selectedID: model.firstSourceID,
                        excludedID: model.secondSourceID,
                        model: model
                    ) { selectedID in
                        model.firstSourceID = selectedID
                    }

                    sourceMenu(
                        title: "次に再生",
                        selectedID: model.secondSourceID,
                        excludedID: model.firstSourceID,
                        model: model
                    ) { selectedID in
                        model.secondSourceID = selectedID
                    }
                }
            }
        }
    }

    private func sourceMenu(
        title: String,
        selectedID: String?,
        excludedID: String?,
        model: ComparisonVideoWindowModel,
        select: @escaping (String?) -> Void
    ) -> some View {
        let selectedSource = model.sources.first { $0.id == selectedID }

        return Menu {
            ForEach(model.sources) { source in
                Button {
                    select(source.id)
                    model.selectionDidChange()
                } label: {
                    if source.id == selectedID {
                        Label(sourceLabel(source), systemImage: "checkmark")
                    } else {
                        Text(sourceLabel(source))
                    }
                }
                .disabled(source.id == excludedID)
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(selectedSource.map(sourceLabel) ?? "選択してください")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
        .accessibilityLabel(title)
        .accessibilityValue(selectedSource.map(sourceLabel) ?? "未選択")
    }

    private func sourceLabel(_ source: ComparisonVideoSource) -> String {
        "\(source.trackTitle)　\(source.roleTitle)"
    }

    @ViewBuilder
    private func rangeSelection(model: ComparisonVideoWindowModel) -> some View {
        if model.isLoading {
            ProgressView("波形を読み込んでいます")
                .controlSize(.small)
        } else if !model.selectionWaveform.isEmpty,
                  model.sourceDuration > 0 {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.sourceDuration <= ComparisonVideoPlan.maximumOutputDuration
                     ? "比較範囲（全体）"
                     : "比較範囲（60秒）")
                    .font(.title3.bold())
                ComparisonVideoRangeView(
                    waveform: model.selectionWaveform,
                    fullDuration: model.sourceDuration,
                    startTime: model.startTime,
                    onStartTimeChange: model.setStartTime
                )
            }
        }
    }

    private func exportSettings(model: ComparisonVideoWindowModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("書き出し")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("向き")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                LiquidGlassSegmentedPicker(
                    title: "向き",
                    options: ComparisonVideoOrientation.allCases,
                    selection: Binding(
                        get: { model.orientation },
                        set: { model.orientation = $0 }
                    ),
                    label: \ComparisonVideoOrientation.title,
                    maxWidth: .infinity
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("形式")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                LiquidGlassSegmentedPicker(
                    title: "形式",
                    options: ComparisonVideoFormat.allCases,
                    selection: Binding(
                        get: { model.format },
                        set: { model.format = $0 }
                    ),
                    label: \ComparisonVideoFormat.title,
                    maxWidth: .infinity
                )
            }
        }
    }

    private func chooseExportDestination(model: ComparisonVideoWindowModel) {
        guard let suggestedFileName = model.suggestedFileName() else { return }
        FilePanelService.chooseSaveLocation(
            suggestedFileName: suggestedFileName,
            allowedContentTypes: [model.format.contentType]
        ) { destinationURL in
            guard let destinationURL else { return }
            model.export(to: destinationURL)
        }
    }

}
