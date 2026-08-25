import SwiftUI

@MainActor
struct StemModelManagementSection: View {
    private enum Layout {
        static let cardMaxWidth: CGFloat = 360
    }

    @Bindable var modelManager: StemModelManager
    let settings: StemSeparationSettings?
    let modelPresentation: StemModeModelPresentation?
    let isDisabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSeparationHelpPresented = false
    @State private var presentedConfirmation: StemModelDownloadConfirmation?
    @State private var confirmationErrorMessage: String?
    @State private var presentedDeletionConfirmation: StemSeparationModel?
    @State private var deletionErrorMessage: String?
    @Namespace private var separationHelpNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Text("Stem分離")
                    .font(.title3.bold())
                Spacer(minLength: 0)
                StemSeparationHelpButton(
                    isPresented: $isSeparationHelpPresented,
                    reduceMotion: reduceMotion,
                    namespace: separationHelpNamespace,
                    selectedModel: modelManager.selectedModel,
                    separationInformation: separationInformation
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

            StemSeparationChoiceGuide(selectedModel: modelManager.selectedModel)

            RecoveryStatusCard(presentation: currentPresentation)
                .alert(
                    "AIモデルを取得できませんでした",
                    isPresented: acquisitionErrorIsPresented
                ) {
                    Button("OK") {
                        confirmationErrorMessage = nil
                    }
                } message: {
                    Text(confirmationErrorMessage ?? "")
                }

            if !managementActions.isEmpty {
                RecoveryActionSection(
                    actions: managementActions,
                    isDisabled: isDisabled
                        || modelManager.isAcquiringModels
                        || !currentPresentation.allowsModelDownload,
                    onAction: performRecoveryAction
                )
                .alert(
                    downloadConfirmationTitle,
                    isPresented: downloadConfirmationIsPresented,
                    presenting: presentedConfirmation
                ) { confirmation in
                    let presentation = DownloadConfirmationPresentation(
                        confirmation: confirmation
                    )
                    Button("キャンセル", role: .cancel) {
                        cancelPendingConfirmation()
                    }
                    Button(presentation.affirmativeTitle) {
                        confirmAcquisition()
                    }
                } message: { confirmation in
                    Text(
                        DownloadConfirmationPresentation(
                            confirmation: confirmation
                        ).alertMessage
                    )
                }
            }

            ModelRemovalActionButton(
                isDisabled: isDisabled
                    || modelManager.isModelOperationInProgress
                    || !modelManager.canRemoveSelectedModel,
                action: prepareModelRemoval
            )
            .alert(
                "AIモデルを削除しますか？",
                isPresented: deletionConfirmationIsPresented,
                presenting: presentedDeletionConfirmation
            ) { model in
                Button("キャンセル", role: .cancel) {
                    presentedDeletionConfirmation = nil
                }
                Button("削除", role: .destructive) {
                    confirmModelRemoval(model)
                }
            } message: { model in
                Text("「\(model.displayName)」を削除します。再利用には再取得が必要です。")
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
        .onChange(of: modelManager.pendingDownloadConfirmation, initial: true) {
            _, confirmation in
            presentedConfirmation = confirmation
        }
        .alert(
            "AIモデルを削除できませんでした",
            isPresented: deletionErrorIsPresented
        ) {
            Button("OK") {
                deletionErrorMessage = nil
            }
        } message: {
            Text(deletionErrorMessage ?? "")
        }
        .accessibilityElement(children: .contain)
    }

    private var currentPresentation: Presentation {
        Presentation.make(inspectionState: modelManager.inspectionState)
    }

    private var deletionConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { presentedDeletionConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    presentedDeletionConfirmation = nil
                }
            }
        )
    }

    private var downloadConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { presentedConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    presentedConfirmation = nil
                }
            }
        )
    }

    private var downloadConfirmationTitle: String {
        guard let presentedConfirmation else {
            return "AIモデルを取得しますか？"
        }
        return DownloadConfirmationPresentation(
            confirmation: presentedConfirmation
        ).title
    }

    private var acquisitionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { confirmationErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    confirmationErrorMessage = nil
                }
            }
        )
    }

    private var deletionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { deletionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    deletionErrorMessage = nil
                }
            }
        )
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
        let selectedModel = settings?.model ?? modelManager.selectedModel
        let modelName = manifest?.model.name
            ?? modelPresentation?.modelName
            ?? selectedModel.displayName
        let revision = manifest?.model.revision
            ?? modelPresentation?.revision
            ?? "--"
        let profile = StemProductionModelProfile.profile(for: selectedModel)
        let roles = modelPresentation?.runContract.separationModel == selectedModel
            ? modelPresentation?.runContract.activeRoles ?? profile.sourceOrder
            : profile.sourceOrder
        let outputDescription = "\(roles.count)Stem（\(roles.map(\.stemModeDisplayTitle).joined(separator: "、"))）"
        if selectedModel == .bsRoformerSW {
            return """
            モデル　\(modelName)
            revision　\(revision)
            方式　STFT／62帯域分割／時間・周波数RoFormer
            出力　\(outputDescription)
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
        出力　\(outputDescription)
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
        confirmationErrorMessage = nil
        switch action {
        case .initialDownload:
            prepareAcquisition(.initialInstall)
        case .repair:
            prepareAcquisition(.repair)
        case .redownload:
            prepareAcquisition(.redownload)
        }
    }

    private func prepareAcquisition(_ purpose: StemModelAcquisitionPurpose) {
        do {
            try modelManager.prepareAcquisitionConfirmation(purpose: purpose)
        } catch {
            confirmationErrorMessage = error.localizedDescription
        }
    }

    private func confirmAcquisition() {
        do {
            try modelManager.confirmAcquisition()
            confirmationErrorMessage = nil
            presentedConfirmation = nil
        } catch {
            modelManager.cancelPendingConfirmation()
            presentedConfirmation = nil
            confirmationErrorMessage = error.localizedDescription
        }
    }

    private func cancelPendingConfirmation() {
        modelManager.cancelPendingConfirmation()
        confirmationErrorMessage = nil
        presentedConfirmation = nil
    }

    private func prepareModelRemoval() {
        guard modelManager.canRemoveSelectedModel else { return }
        deletionErrorMessage = nil
        presentedDeletionConfirmation = modelManager.selectedModel
    }

    private func confirmModelRemoval(_ model: StemSeparationModel) {
        deletionErrorMessage = nil
        presentedDeletionConfirmation = nil
        Task {
            do {
                try await modelManager.removeSelectedModel(
                    expectedModel: model
                )
            } catch {
                deletionErrorMessage = error.localizedDescription
            }
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
                    message: "Stem Modeを使うには、固定RevisionのAIモデル2資産が必要です。取得を承認するまでネットワーク通信は開始しません。",
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
                    message: "AIモデル2資産を取得し直す必要があります。承認した後にだけ完全再取得を開始します。",
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

    struct DownloadConfirmationPresentation: Equatable, Sendable {
        let title: String
        let affirmativeTitle: String
        let alertMessage: String

        init(confirmation: StemModelDownloadConfirmation) {
            switch confirmation.purpose {
            case .initialInstall:
                title = "AIモデルを取得しますか？"
                affirmativeTitle = "取得"
                alertMessage = "Stem分離に必要なAIモデルを取得します。"
            case .repair:
                title = "AIモデルを修復しますか？"
                affirmativeTitle = "修復"
                alertMessage = "選択中のAIモデルを取得し直します。"
            case .redownload:
                title = "AIモデルを再取得しますか？"
                affirmativeTitle = "再取得"
                alertMessage = "選択中のAIモデルを再取得します。"
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
                help = "選択中モデルを取得する前の確認を開きます。承認するまで通信しません。"
                isPrimary = true
            case .repair:
                title = "AIモデルを修復"
                systemImage = "wrench.and.screwdriver"
                help = "欠落・破損したAIモデル2資産の取得確認を開きます。"
                isPrimary = true
            case .redownload:
                title = "AIモデルを取得"
                systemImage = "arrow.clockwise.circle"
                help = "選択中モデルのAIモデル2資産を完全再取得する確認を開きます。"
                isPrimary = false
            }
        }
    }
}

private extension StemModelManagementSection {
    struct StemSeparationChoiceGuide: View {
        let selectedModel: StemSeparationModel

        var body: some View {
            Group {
                if selectedModel == .htdemucs {
                    ChoiceRow(
                        title: "HTDemucs",
                        emphasis: "安定・実績・バランス重視",
                        detail: "はじめやすさや、全体のバランスを重視する場合に。",
                        color: .pink
                    )
                } else {
                    ChoiceRow(
                        title: "BS-RoFormer-SW",
                        emphasis: "精度・細かさ・分離感重視",
                        detail: "ボーカルや楽器を、より細かく分けたい場合に。",
                        color: .blue
                    )
                }
            }
            .padding(12)
            .frame(maxWidth: Layout.cardMaxWidth, alignment: .leading)
            .velouraAdaptiveGlass(in: .rect(cornerRadius: 16))
            .accessibilityElement(children: .contain)
        }
    }

    struct ChoiceRow: View {
        let title: String
        let emphasis: String
        let detail: String
        let color: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(color)
                Text(emphasis)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    struct StemSeparationHelpButton: View {
        @Binding var isPresented: Bool
        let reduceMotion: Bool
        let namespace: Namespace.ID
        let selectedModel: StemSeparationModel
        let separationInformation: String

        var body: some View {
            Button {
                LiquidGlassMotion.perform(
                    reduceMotion: reduceMotion,
                    animation: LiquidGlassMotion.panel
                ) {
                    isPresented.toggle()
                }
            } label: {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .glassEffect(.clear.interactive(), in: Circle())
                    .liquidGlassEffectID("stem-separation-help", in: namespace, isActive: !isPresented)
                    .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stem分離モデルの詳しい比較")
            .help("Stem分離モデルの仕組み・特徴・比較を表示します")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                StemSeparationHelpContent(
                    selectedModel: selectedModel,
                    separationInformation: separationInformation
                )
                    .frame(width: 480, height: 560)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
                    .glassEffectID("stem-separation-help", in: namespace)
                    .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
            }
        }
    }

    struct StemSeparationHelpContent: View {
        let selectedModel: StemSeparationModel
        let separationInformation: String

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Stem分離モデルの詳しい比較")
                        .font(.title3.bold())

                    HelpSection(title: "仕組み") {
                        selectedModelDescription
                    }

                    HelpSection(title: "\(selectedModel.displayName)の特徴") {
                        HelpBulletList(items: selectedModelFeatures)
                    }

                    HelpSection(title: "違い") {
                        ComparisonTable()
                    }

                    Text("分離結果は、楽曲、録音状態、音の重なり方によって変わります。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .velouraAdaptiveGlass(in: .rect(cornerRadius: 12))

                    HelpSection(title: "選択中モデルの詳細情報") {
                        Text(separationInformation)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
            }
            .accessibilityElement(children: .contain)
        }

        @ViewBuilder
        private var selectedModelDescription: some View {
            switch selectedModel {
            case .htdemucs:
                HelpModelDescription(
                    title: "HTDemucs",
                    description: "音の波形と、周波数ごとの音の分布を組み合わせて判断するモデルです。"
                )
            case .bsRoformerSW:
                HelpModelDescription(
                    title: "BS-RoFormer-SW",
                    description: "音を周波数帯に分け、時間と周波数の関係を見ながら判断するモデルです。"
                )
            }
        }

        private var selectedModelFeatures: [String] {
            switch selectedModel {
            case .htdemucs:
                [
                    "定番として使われているモデル",
                    "関連する情報や実装例が多い",
                    "全体のバランスを重視した分離",
                    "比較的扱いやすい",
                ]
            case .bsRoformerSW:
                [
                    "音を細かく捉えることを重視",
                    "ボーカルや楽器の分離感を求める場合に向く",
                    "音のにじみや混ざりを減らすことを狙う",
                    "音の細部を分けたい場合に有力",
                ]
            }
        }
    }

    struct HelpSection<Content: View>: View {
        let title: String
        @ViewBuilder let content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.title3.bold())
                content
            }
        }
    }

    struct HelpModelDescription: View {
        let title: String
        let description: String

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.bold())
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    struct HelpBulletList: View {
        let items: [String]

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(item)
                            .font(.body)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    struct ComparisonTable: View {
        private let rows = [
            ("設計", "波形と周波数情報を組み合わせる方式", "時間と周波数の関係を見る方式"),
            ("分離の方向性", "全体のバランスを重視", "細かな分離感を重視"),
            ("情報の多さ", "定番で関連情報が多い", "比較的新しい方式"),
            ("扱い方", "比較的扱いやすい", "細部まで分けたい場合に使う"),
        ]

        var body: some View {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("比較する点")
                    Text("HTDemucs")
                    Text("BS-RoFormer-SW")
                }
                .font(.title3.bold())

                Divider().gridCellColumns(3)

                ForEach(rows, id: \.0) { row in
                    GridRow(alignment: .top) {
                        Text(row.0).fontWeight(.semibold)
                        Text(row.1)
                        Text(row.2)
                    }
                    .font(.body)
                    Divider().gridCellColumns(3)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

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
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(toneColor)
                    }
                }
                .font(.title3)

                Text(presentation.title)
                    .font(.title3.bold())
                Text(presentation.message)
                    .font(.body)
                    .foregroundStyle(.secondary)

                if let detail = presentation.detail {
                    LabeledContent {
                        Text(detail)
                            .font(.body)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    } label: {
                        Text("確認結果")
                            .font(.title3)
                    }
                    .foregroundStyle(.secondary)
                }

                if presentation.requiresAppReinstallation {
                    Label(
                        "この状態が続く場合は、アプリを正規配布物から再インストールしてください。AIモデルの再取得では直りません。",
                        systemImage: "arrow.down.app"
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(12)
            .frame(maxWidth: Layout.cardMaxWidth, alignment: .leading)
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

    struct ModelRemovalActionButton: View {
        let isDisabled: Bool
        let action: () -> Void

        var body: some View {
            LiquidGlassActionButton(
                title: "AIモデルを削除",
                systemImage: "trash",
                isDisabled: isDisabled,
                layout: .inspectorWide,
                action: action
            )
            .foregroundStyle(.red)
            .help(
                isDisabled
                    ? "選択中モデルに削除できる取得データがないか、モデル操作・Stem処理が進行中です。"
                    : "選択中モデルの取得データを削除する確認を開きます。"
            )
            .accessibilityHint("もう一方のモデルと作成済み音声は削除しません。")
        }
    }

}
