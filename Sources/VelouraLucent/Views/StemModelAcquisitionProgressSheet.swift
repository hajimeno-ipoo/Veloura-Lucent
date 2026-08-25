import Foundation
import SwiftUI

@MainActor
struct StemModelAcquisitionProgressSheet: View {
    @Bindable var modelManager: StemModelManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isCancellationHovering = false
    @FocusState private var isCancellationFocused: Bool
    @Namespace private var cancellationGlassNamespace

    var body: some View {
        modalSurface
            .padding(12)
            .accessibilityElement(children: .contain)
    }

    private var modalSurface: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            switch modelManager.operationState {
            case .acquiring(let progress):
                acquisitionControls(progress: progress, isCancelling: false)
            case .cancelling(let progress):
                acquisitionControls(progress: progress, isCancelling: true)
            case .failed(let message, let retryPurpose):
                destinationCard()
                failureCard(
                    message: message,
                    canRetryDownload: retryPurpose != nil
                )
            case .idle, .awaitingConfirmation:
                destinationCard()
            }
        }
        .padding(20)
        .frame(minWidth: 660, maxWidth: 660, minHeight: 240)
        .velouraAdaptiveGlass(in: .rect(cornerRadius: 28))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AIモデルを取得")
                .font(.title2.bold())
            Text(modelManager.selectedModel.displayName)
                .font(.title3.bold())
                .foregroundStyle(.secondary)
        }
    }

    private func destinationCard(
        presentation: StemModelManagementSection.ProgressPresentation? = nil,
        isCancelling: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                detailValue(
                    label: "保存先",
                    value: NSString(
                        string: StemModelStorePaths.production.rootURL.path
                    ).abbreviatingWithTildeInPath
                )

                Text("取得するファイル")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                ForEach(assetFileNames, id: \.self) { fileName in
                    Label(fileName, systemImage: "doc")
                        .font(.body.monospaced())
                }
            }

            Spacer(minLength: 8)

            if let presentation {
                acquisitionIndicator(
                    presentation: presentation,
                    isCancelling: isCancelling
                )
            }
        }
        .padding(14)
        .velouraAdaptiveGlass(in: .rect(cornerRadius: 16))
    }

    private func acquisitionControls(
        progress: StemModelAcquisitionProgress,
        isCancelling: Bool
    ) -> some View {
        let presentation = StemModelManagementSection.ProgressPresentation.make(
            progress: progress,
            manifest: modelManager.localInspection?.validatedManifest,
            isCancelling: isCancelling
        )

        return HStack(alignment: .center, spacing: 14) {
            destinationCard(
                presentation: presentation,
                isCancelling: isCancelling
            )
            .frame(maxWidth: .infinity)

            if presentation.canRequestCancellation || isCancelling {
                cancellationButton(isCancelling: isCancelling)
            }
        }
    }

    @ViewBuilder
    private func acquisitionIndicator(
        presentation: StemModelManagementSection.ProgressPresentation,
        isCancelling: Bool
    ) -> some View {
        if presentation.phase == .completed && !isCancelling {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .accessibilityLabel("AIモデル取得完了")
        } else {
            ProgressView()
                .controlSize(.regular)
                .accessibilityLabel(
                    isCancelling
                        ? "AIモデル取得を中断中"
                        : presentation.stageTitle
                )
        }
    }

    private func cancellationButton(isCancelling: Bool) -> some View {
        GlassEffectContainer(spacing: 0) {
            Button {
                guard !isCancelling else { return }
                modelManager.requestAcquisitionCancellation()
            } label: {
                Label("キャンセル", systemImage: "xmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
                    .foregroundStyle(
                        isCancellationHovering && !isCancelling
                            ? Color.white
                            : Color.red
                    )
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .modifier(
                        CancellationLiquidGlassHoverModifier(
                            isActive: isCancellationHovering && !isCancelling,
                            effectID: "hover-liquid-glass-model-acquisition-cancel",
                            namespace: cancellationGlassNamespace,
                            reduceMotion: reduceMotion
                        )
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isCancelling)
            .onHover {
                updateCancellationHover($0, isCancelling: isCancelling)
            }
            .focused($isCancellationFocused)
            .help("AIモデルの取得をキャンセルします")
            .accessibilityLabel("AIモデル取得をキャンセル")
            .keyboardShortcut(.cancelAction)
        }
        .padding(4)
        .velouraAdaptiveGlass(in: .capsule, interactive: !isCancelling)
        .task {
            await Task.yield()
            isCancellationFocused = false
        }
    }

    @MainActor
    private func updateCancellationHover(
        _ hovering: Bool,
        isCancelling: Bool
    ) {
        let nextValue = hovering && !isCancelling
        guard isCancellationHovering != nextValue else { return }

        LiquidGlassMotion.perform(
            reduceMotion: reduceMotion,
            animation: LiquidGlassMotion.selection
        ) {
            isCancellationHovering = nextValue
        }
    }

    private func failureCard(
        message: String,
        canRetryDownload: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("モデル取得に失敗しました", systemImage: "exclamationmark.triangle")
                .font(.title3.bold())
                .foregroundStyle(.red)
            Text(message)
                .font(.body)
                .textSelection(.enabled)
            Text("既存の検証済みモデルは維持されています。")
                .font(.body)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                if canRetryDownload {
                    LiquidGlassActionButton(
                        title: "再ダウンロード",
                        systemImage: "arrow.clockwise",
                        action: modelManager.retryFailedAcquisition
                    )
                    .keyboardShortcut(.defaultAction)
                }
                LiquidGlassActionButton(
                    title: "閉じる",
                    systemImage: "xmark",
                    action: modelManager.dismissFailure
                )
            }
        }
        .padding(16)
        .velouraAdaptiveGlass(
            in: .rect(cornerRadius: 16),
            tint: .red.opacity(0.08)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.red.opacity(0.35))
                .allowsHitTesting(false)
        }
    }

    private var assetFileNames: [String] {
        let assets = modelManager.localInspection?.validatedManifest?
            .downloadableModelAssets
            ?? StemProductionModelProfile.profile(
                for: modelManager.selectedModel
            ).downloadableAssets.values.map { $0 }
        return assets
            .sorted {
                assetSortOrder($0.kind) < assetSortOrder($1.kind)
            }
            .map {
                URL(fileURLWithPath: $0.installationRelativePath)
                    .lastPathComponent
            }
    }

    private func assetSortOrder(_ kind: StemModelAssetKind) -> Int {
        switch kind {
        case .modelWeights: 0
        case .modelConfiguration: 1
        case .metalLibrary: 2
        }
    }

    private func detailValue(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospaced())
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CancellationLiquidGlassHoverModifier: ViewModifier {
    let isActive: Bool
    let effectID: String
    let namespace: Namespace.ID
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if isActive {
            content
                .glassEffect(
                    .regular.tint(.red.opacity(0.58)).interactive(),
                    in: .capsule
                )
                .glassEffectID(effectID, in: namespace)
                .glassEffectTransition(
                    reduceMotion ? .identity : .matchedGeometry
                )
        } else {
            content
        }
    }
}
