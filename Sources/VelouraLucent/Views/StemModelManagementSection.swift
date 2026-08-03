import SwiftUI

@MainActor
struct StemModelManagementSection: View {
    @Bindable var modelManager: StemModelManager
    let settings: StemSeparationSettings?
    let modelPresentation: StemModeModelPresentation?
    let isDisabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Text("Stem分離")
                    .font(.headline)
                Spacer(minLength: 0)
                TermHelpButton(
                    title: "Stem分離情報",
                    reading: "現在使用するモデルと分離設定",
                    description: separationInformation,
                    systemImage: "exclamationmark.circle"
                )
            }

            LiquidGlassSegmentedPicker(
                title: "分離モデル",
                options: StemSeparationModel.allCases,
                selection: selectedModelBinding,
                label: \.displayName,
                isDisabled: isDisabled
                    || modelManager.isAcquiringModels
            )

            RecoveryStatusCard(presentation: currentPresentation)

            if !managementActions.isEmpty {
                RecoveryActionSection(
                    actions: managementActions,
                    isDisabled: isDisabled
                        || modelManager.isAcquiringModels
                        || !currentPresentation.allowsModelDownload,
                    onAction: performRecoveryAction
                )
            }
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
        .task {
            guard case .checking = modelManager.inspectionState else { return }
            await modelManager.inspectLocalResources()
        }
        .accessibilityElement(children: .contain)
    }

    private var currentPresentation: Presentation {
        Presentation.make(inspectionState: modelManager.inspectionState)
    }

    private var selectedModelBinding: Binding<StemSeparationModel> {
        Binding(
            get: { modelManager.selectedModel },
            set: { model in
                Task { await modelManager.selectModel(model) }
            }
        )
    }

    private var managementActions: [StemModelRecoveryAction] {
        currentPresentation.visibleActions
    }

    private var separationInformation: String {
        let manifest = modelManager.localInspection?.validatedManifest
        let modelName = manifest?.model.name
            ?? modelPresentation?.modelName
            ?? modelManager.selectedModel.displayName
        let revision = manifest?.model.revision
            ?? modelPresentation?.revision
            ?? "--"
        if settings?.model == .bsRoformerSW
            || modelManager.selectedModel == .bsRoformerSW {
            return """
            モデル　\(modelName)
            revision　\(revision)
            方式　STFT／62帯域分割／時間・周波数RoFormer
            出力　6Stem → 既存4Stem
            設定（固定）　STFT FFT / hop / window　2048 / 512 / 2048
            　　　　　　帯域 / 周波数ビン　　　 62 / 1025
            　　　　　　推論チャンク　　　　　 801フレーム
            　　　　　　短音源 / ステップ　　　 10秒未満: 256フレーム / 8秒
            　　　　　　dim / depth / heads　　 256 / 12 / 8
            """
        }

        let displayedSettings = settings ?? StemSeparationSettings(
            shifts: 2,
            overlap: 0.25,
            split: true,
            segmentLength: .modelContract,
            batchSize: 1,
            seed: nil
        )
        let shiftsAndOverlap =
            "\(displayedSettings.shifts) / \(displayedSettings.overlap.formatted(.number.precision(.fractionLength(2))))"
        let splitAndSegment =
            "\(displayedSettings.split ? "true" : "false") / \(segmentText(displayedSettings))"
        let seed = displayedSettings.seed?.formatted(.number.grouping(.never))
            ?? "入力選択後に生成"
        let batchSizeAndSeed = "\(displayedSettings.batchSize) / \(seed)"
        return """
        モデル　\(modelName)
        revision　\(revision)
        方式　Demucs v4
        出力　4Stem
        設定　shifts / overlap　\(shiftsAndOverlap)
        　　　split / segment　\(splitAndSegment)
        　　　batch size / run seed　\(batchSizeAndSeed)
        """
    }

    private func segmentText(_ settings: StemSeparationSettings) -> String {
        switch settings.segmentLength {
        case .modelContract:
            "\(StemSeparationSettings.verifiedModelContractSegmentSeconds.formatted(.number.precision(.fractionLength(1))))秒"
        case .seconds(let seconds):
            "\(seconds.formatted(.number.precision(.fractionLength(1))))秒"
        }
    }

    private func performRecoveryAction(_ action: StemModelRecoveryAction) {
        switch action {
        case .initialDownload:
            modelManager.startAcquisition(purpose: .initialInstall)
        case .repair:
            modelManager.startAcquisition(purpose: .repair)
        case .redownload:
            modelManager.startAcquisition(purpose: .redownload)
        }
    }
}

extension StemModelManagementSection {
    struct Presentation: Equatable, Sendable {
        enum Tone: Equatable, Sendable {
            case neutral
            case success
            case warning
            case error
        }

        let title: String
        let statusText: String
        let message: String
        let detail: String?
        let symbolName: String
        let tone: Tone
        let isChecking: Bool
        let requiresAppReinstallation: Bool
        let actions: [StemModelRecoveryAction]

        var allowsModelDownload: Bool {
            actions.contains(.initialDownload)
                || actions.contains(.repair)
                || actions.contains(.redownload)
        }

        var visibleActions: [StemModelRecoveryAction] {
            guard actions.isEmpty, tone == .success else { return actions }
            return [.initialDownload]
        }

        static func make(inspectionState: StemModelInspectionState) -> Self {
            switch inspectionState {
            case .checking:
                return Presentation(
                    title: "Stem Mode資産を確認中",
                    statusText: "確認中",
                    message: "AIモデル、固定Revision、SHA-256、同梱MLX実行資産をローカルだけで確認しています。",
                    detail: nil,
                    symbolName: "magnifyingglass",
                    tone: .neutral,
                    isChecking: true,
                    requiresAppReinstallation: false,
                    actions: []
                )

            case .loaded(let inspection):
                return make(inspection: inspection)
            }
        }

        private static func make(inspection: StemModelLocalInspection) -> Self {
            if case .unsupported(let processArchitecture) = inspection.platform {
                return Presentation(
                    title: "このMacではStem Modeを実行できません",
                    statusText: "利用不可",
                    message: "Stem ModeはApple Silicon専用です。現在の実行アーキテクチャではAIモデルを取得せず、通常モードだけを利用できます。",
                    detail: "実行アーキテクチャ: \(processArchitecture)",
                    symbolName: "cpu",
                    tone: .warning,
                    isChecking: false,
                    requiresAppReinstallation: false,
                    actions: inspection.recoveryActions
                )
            }

            if case .invalid(let message) = inspection.manifest {
                return Presentation(
                    title: "モデル定義を検証できません",
                    statusText: "要確認",
                    message: "同梱manifestが正しくないため、AIモデルの取得は開始できません。通常モードは引き続き利用できます。",
                    detail: message,
                    symbolName: "doc.badge.ellipsis",
                    tone: .error,
                    isChecking: false,
                    requiresAppReinstallation: true,
                    actions: inspection.recoveryActions
                )
            }

            switch inspection.bundledRuntime {
            case .invalid(let message):
                return Presentation(
                    title: "MLX実行資産を検証できません",
                    statusText: "要確認",
                    message: "アプリ同梱のMLX実行資産に問題があります。AIモデルの再取得では修復できないため、Stem推論は開始しません。通常モードを利用するか、アプリを正規配布物から再インストールしてください。",
                    detail: message,
                    symbolName: "shippingbox.and.arrow.backward",
                    tone: .error,
                    isChecking: false,
                    requiresAppReinstallation: true,
                    actions: inspection.recoveryActions
                )
            case .notChecked:
                return Presentation(
                    title: "MLX実行資産の状態を確認できません",
                    statusText: "未確認",
                    message: "AIモデルの取得は開始しません。この状態が続く場合は、アプリを正規配布物から再インストールしてください。通常モードは利用できます。",
                    detail: nil,
                    symbolName: "shippingbox",
                    tone: .warning,
                    isChecking: false,
                    requiresAppReinstallation: true,
                    actions: inspection.recoveryActions
                )
            case .ready:
                break
            }

            switch inspection.installedModel {
            case .notChecked:
                return Presentation(
                    title: "AIモデルの状態を確認できません",
                    statusText: "未確認",
                    message: "AIモデルの取得は開始しません。通常モードへ切り替えることもできます。",
                    detail: nil,
                    symbolName: "questionmark.folder",
                    tone: .warning,
                    isChecking: false,
                    requiresAppReinstallation: false,
                    actions: inspection.recoveryActions
                )
            case .missing:
                return Presentation(
                    title: "AIモデルが必要です",
                    statusText: "未取得",
                    message: "Stem Modeを使うには、固定RevisionのAIモデル2資産が必要です。取得ボタンを押すと通信を開始し、ファイル名、保存先、進捗をモーダルへ表示します。",
                    detail: nil,
                    symbolName: "arrow.down.circle",
                    tone: .warning,
                    isChecking: false,
                    requiresAppReinstallation: false,
                    actions: inspection.recoveryActions
                )
            case .invalid(let message):
                return Presentation(
                    title: "AIモデルの修復が必要です",
                    statusText: "修復必要",
                    message: "AIモデル2資産を取得し直す必要があります。取得ボタンを押すと、進捗画面を表示して完全再取得を開始します。",
                    detail: message,
                    symbolName: "wrench.and.screwdriver",
                    tone: .error,
                    isChecking: false,
                    requiresAppReinstallation: false,
                    actions: inspection.recoveryActions
                )
            case .ready:
                return Presentation(
                    title: "Stem Modeのモデルを利用できます",
                    statusText: "利用可能",
                    message: "AIモデル2資産と同梱MLX実行資産は検証済みです。再取得は必要ありません。",
                    detail: nil,
                    symbolName: "checkmark.seal",
                    tone: .success,
                    isChecking: false,
                    requiresAppReinstallation: false,
                    actions: inspection.recoveryActions
                )
            }
        }
    }

    struct ProgressPresentation: Equatable, Sendable {
        struct AssetProgress: Equatable, Sendable, Identifiable {
            let kind: StemModelAssetKind
            let fileName: String
            let fraction: Double
            let receivedBytes: Int64
            let totalBytes: Int64
            let isCurrent: Bool

            var id: StemModelAssetKind { kind }
        }

        let stageTitle: String
        let stageDetail: String
        let phase: StemModelAcquisitionProgress.Phase
        let overallFraction: Double
        let receivedBytes: Int64
        let totalBytes: Int64
        let assetProgresses: [AssetProgress]
        let isWaitingForConnectivity: Bool
        let canRequestCancellation: Bool

        static func make(
            progress: StemModelAcquisitionProgress,
            manifest: StemModelManifest?,
            isCancelling: Bool
        ) -> Self {
            let totalBytes = max(progress.totalBytes, 0)
            let receivedBytes = min(max(progress.receivedBytes, 0), totalBytes)
            let overallFraction = fraction(received: receivedBytes, total: totalBytes)

            let stageTitle: String
            let stageDetail: String
            if isCancelling {
                stageTitle = "モデル取得を中断しています"
                stageDetail = "検証済みactive世代は維持し、取得途中のstagingだけを安全に片付けています。"
            } else if progress.isWaitingForConnectivity {
                stageTitle = "ネットワーク接続を待っています"
                stageDetail = "接続が戻るまで待機しています。通常モードの利用は妨げません。"
            } else {
                switch progress.phase {
                case .preparing:
                    stageTitle = "モデル取得を準備中"
                    stageDetail = "取得用の一時領域を準備しています。検証済みactive世代は変更しません。"
                case .downloading:
                    stageTitle = "AIモデルを取得中"
                    stageDetail = "固定Revisionの2資産を順番に取得しています。"
                case .validating:
                    stageTitle = "取得済み資産を検証中"
                    stageDetail = "2資産の容量、固定Revision、SHA-256を検証しています。"
                case .activating:
                    stageTitle = "検証済みモデルを有効化中（中断不可）"
                    stageDetail = "2資産を一組としてactive世代へ原子的に切り替えています。このcommit中は安全のため中断できません。"
                case .completed:
                    stageTitle = "モデル取得が完了しました"
                    stageDetail = "有効化した2資産をローカルで再検証しています。"
                }
            }

            let assetProgresses = makeAssetProgresses(
                progress: progress,
                manifest: manifest
            )
            return ProgressPresentation(
                stageTitle: stageTitle,
                stageDetail: stageDetail,
                phase: progress.phase,
                overallFraction: overallFraction,
                receivedBytes: receivedBytes,
                totalBytes: totalBytes,
                assetProgresses: assetProgresses,
                isWaitingForConnectivity: progress.isWaitingForConnectivity,
                canRequestCancellation: progress.phase != .activating
                    && progress.phase != .completed
                    && !isCancelling
            )
        }

        private static func makeAssetProgresses(
            progress: StemModelAcquisitionProgress,
            manifest: StemModelManifest?
        ) -> [AssetProgress] {
            guard let manifest else { return [] }
            let orderedAssets = manifest.downloadableModelAssets.sorted {
                assetSortOrder($0.kind) < assetSortOrder($1.kind)
            }
            var completedBeforeAsset: Int64 = 0
            return orderedAssets.map { asset in
                let assetByteCount = max(asset.byteCount, 0)
                let (difference, underflow) = progress.receivedBytes
                    .subtractingReportingOverflow(completedBeforeAsset)
                let received = underflow
                    ? 0
                    : min(max(difference, 0), assetByteCount)
                let item = AssetProgress(
                    kind: asset.kind,
                    fileName: URL(fileURLWithPath: asset.installationRelativePath)
                        .lastPathComponent,
                    fraction: fraction(received: received, total: assetByteCount),
                    receivedBytes: received,
                    totalBytes: assetByteCount,
                    isCurrent: progress.assetKind == asset.kind
                )
                let (sum, overflow) = completedBeforeAsset
                    .addingReportingOverflow(assetByteCount)
                completedBeforeAsset = overflow ? Int64.max : sum
                return item
            }
        }

        private static func fraction(received: Int64, total: Int64) -> Double {
            guard total > 0 else { return 0 }
            return min(max(Double(received) / Double(total), 0), 1)
        }

        private static func assetSortOrder(_ kind: StemModelAssetKind) -> Int {
            switch kind {
            case .modelWeights: 0
            case .modelConfiguration: 1
            case .metalLibrary: 2
            }
        }
    }

    struct ActionPresentation: Equatable, Sendable {
        let action: StemModelRecoveryAction
        let title: String
        let systemImage: String
        let help: String
        let isPrimary: Bool

        init(action: StemModelRecoveryAction) {
            self.action = action
            switch action {
            case .initialDownload:
                title = "AIモデルを取得"
                systemImage = "arrow.down.circle"
                help = "選択中モデルの取得を開始し、進捗画面を開きます。"
                isPrimary = true
            case .repair:
                title = "AIモデルを修復"
                systemImage = "wrench.and.screwdriver"
                help = "欠落・破損したAIモデル2資産を取得し直します。"
                isPrimary = true
            case .redownload:
                title = "AIモデルを取得"
                systemImage = "arrow.clockwise.circle"
                help = "選択中モデルのAIモデル2資産を完全再取得します。"
                isPrimary = false
            }
        }
    }
}

private extension StemModelManagementSection {
    struct RecoveryStatusCard: View {
        let presentation: Presentation

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("モデル状態") {
                    HStack(spacing: 6) {
                        if presentation.isChecking {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Stem Mode資産を確認中")
                        } else {
                            Image(systemName: presentation.symbolName)
                                .foregroundStyle(toneColor)
                                .accessibilityHidden(true)
                        }
                        Text(presentation.statusText)
                            .fontWeight(.semibold)
                            .foregroundStyle(toneColor)
                    }
                }

                Text(presentation.title)
                    .font(.callout.bold())
                Text(presentation.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let detail = presentation.detail {
                    LabeledContent("確認結果") {
                        Text(detail)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                if presentation.requiresAppReinstallation {
                    Label(
                        "この状態が続く場合は、アプリを正規配布物から再インストールしてください。AIモデルの再取得では直りません。",
                        systemImage: "arrow.down.app"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(12)
            .velouraAdaptiveGlass(in: .rect(cornerRadius: 16))
            .accessibilityElement(children: .contain)
        }

        private var toneColor: Color {
            switch presentation.tone {
            case .neutral: .secondary
            case .success: .green
            case .warning: .orange
            case .error: .red
            }
        }
    }

    struct RecoveryActionSection: View {
        let actions: [StemModelRecoveryAction]
        let isDisabled: Bool
        let onAction: (StemModelRecoveryAction) -> Void

        var body: some View {
            HStack(spacing: 10) {
                ForEach(actions) { action in
                    RecoveryActionButton(
                        presentation: ActionPresentation(action: action),
                        action: { onAction(action) }
                    )
                }
            }
            .disabled(isDisabled)
        }
    }

    struct RecoveryActionButton: View {
        let presentation: ActionPresentation
        let action: () -> Void

        var body: some View {
            if presentation.isPrimary {
                LiquidGlassActionButton(
                    title: presentation.title,
                    systemImage: presentation.systemImage,
                    layout: .inspectorWide,
                    action: action
                )
                .keyboardShortcut(.defaultAction)
                .help(presentation.help)
            } else {
                LiquidGlassActionButton(
                    title: presentation.title,
                    systemImage: presentation.systemImage,
                    layout: .inspectorWide,
                    action: action
                )
                .help(presentation.help)
            }
        }
    }

}
