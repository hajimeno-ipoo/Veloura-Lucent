import SwiftUI

@MainActor
struct StemModelManagementSection: View {
    @Bindable var modelManager: StemModelManager
    let settings: StemSeparationSettings?
    let modelPresentation: StemModeModelPresentation?
    let isDisabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentedConfirmation: StemModelDownloadConfirmation?
    @State private var localErrorMessage: String?

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

            RecoveryStatusCard(presentation: currentPresentation)

            if let progressContext {
                AcquisitionProgressCard(
                    presentation: progressContext.presentation,
                    isCancelling: progressContext.isCancelling,
                    onCancel: modelManager.requestAcquisitionCancellation
                )
            }

            if let displayedErrorMessage {
                RecoveryFailureCard(
                    message: displayedErrorMessage,
                    onDismiss: dismissDisplayedError
                )
            }

            if !modelManager.isAcquiringModels {
                RecoveryActionSection(
                    actions: managementActions,
                    isDisabled: isDisabled || presentedConfirmation != nil,
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
        .onChange(of: modelManager.pendingDownloadConfirmation, initial: true) {
            _, newConfirmation in
            synchronizeConfirmation(with: newConfirmation)
        }
        .sheet(item: $presentedConfirmation, onDismiss: confirmationDidDismiss) { confirmation in
            ModelDownloadConfirmationSheet(
                confirmation: confirmation,
                errorMessage: localErrorMessage,
                onConfirm: confirmAcquisition,
                onCancel: cancelPendingConfirmation
            )
        }
        .accessibilityElement(children: .contain)
    }

    private var currentPresentation: Presentation {
        Presentation.make(inspectionState: modelManager.inspectionState)
    }

    private var managementActions: [StemModelRecoveryAction] {
        currentPresentation.actions
    }

    private var separationInformation: String {
        let manifest = modelManager.localInspection?.validatedManifest
        let modelName = manifest?.model.name
            ?? modelPresentation?.modelName
            ?? "確認中"
        let revision = manifest?.model.revision
            ?? modelPresentation?.revision
            ?? "--"
        let displayedSettings = settings ?? StemSeparationSettings(
            shifts: 1,
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
        shifts / overlap　\(shiftsAndOverlap)
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

    private var displayedErrorMessage: String? {
        if let localErrorMessage {
            return localErrorMessage
        }
        guard case .failed(let message) = modelManager.operationState else {
            return nil
        }
        return message
    }

    private var progressContext: ProgressContext? {
        let progress: StemModelAcquisitionProgress
        let isCancelling: Bool
        switch modelManager.operationState {
        case .acquiring(let current):
            progress = current
            isCancelling = false
        case .cancelling(let current):
            progress = current
            isCancelling = true
        case .idle, .awaitingConfirmation, .failed:
            return nil
        }

        return ProgressContext(
            presentation: ProgressPresentation.make(
                progress: progress,
                manifest: modelManager.localInspection?.validatedManifest,
                isCancelling: isCancelling
            ),
            isCancelling: isCancelling
        )
    }

    private func performRecoveryAction(_ action: StemModelRecoveryAction) {
        localErrorMessage = nil
        switch action {
        case .initialDownload:
            prepareAcquisition(.initialInstall)
        case .repair:
            prepareAcquisition(.repair)
        case .redownload:
            prepareAcquisition(.redownload)
        case .revalidate:
            modelManager.dismissFailure()
            Task {
                await modelManager.inspectLocalResources()
            }
        }
    }

    private func prepareAcquisition(_ purpose: StemModelAcquisitionPurpose) {
        do {
            try modelManager.prepareAcquisitionConfirmation(purpose: purpose)
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }

    private func confirmAcquisition() {
        do {
            // This affirmative sheet action is the only UI path that issues the
            // one-operation network authorization and starts model acquisition.
            try modelManager.confirmAcquisition()
            localErrorMessage = nil
            presentedConfirmation = nil
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }

    private func cancelPendingConfirmation() {
        modelManager.cancelPendingConfirmation()
        localErrorMessage = nil
        presentedConfirmation = nil
    }

    private func confirmationDidDismiss() {
        modelManager.cancelPendingConfirmation()
        localErrorMessage = nil
    }

    private func synchronizeConfirmation(
        with confirmation: StemModelDownloadConfirmation?
    ) {
        presentedConfirmation = confirmation
    }

    private func dismissDisplayedError() {
        localErrorMessage = nil
        modelManager.dismissFailure()
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
                    message: "AIモデルの取得は開始しません。再検証しても確認できない場合は、アプリを正規配布物から再インストールしてください。通常モードは利用できます。",
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
                    message: "取得を始めずに再検証してください。通常モードへ切り替えることもできます。",
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
                    message: "Stem Modeを使うには、固定RevisionのAIモデル2資産を取得する必要があります。取得内容を確認し、承認するまでネットワーク通信は開始しません。",
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
                    message: "欠落・破損状態を修復するか、AIモデル2資産を完全再取得できます。どちらも取得する2資産の確認と承認後にのみ通信を開始します。",
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
                    message: "AIモデル2資産と同梱MLX実行資産は検証済みです。必要な場合は、確認画面を経てAIモデル2資産を完全再取得できます。",
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
        struct Asset: Equatable, Sendable, Identifiable {
            let kind: StemModelAssetKind
            let fileName: String
            let byteCount: Int64
            let sha256: String
            let stableDownloadURL: String

            var id: StemModelAssetKind { kind }
        }

        let title: String
        let affirmativeTitle: String
        let repository: String
        let revision: String
        let license: String
        let totalByteCount: Int64
        let sourceHost: String?
        let assets: [Asset]
        let networkNotice: String

        init(confirmation: StemModelDownloadConfirmation) {
            switch confirmation.purpose {
            case .initialInstall:
                title = "Stem Mode AIモデルを取得"
                affirmativeTitle = "取得を開始"
            case .repair:
                title = "Stem Mode AIモデルを修復"
                affirmativeTitle = "修復を開始"
            case .redownload:
                title = "Stem Mode AIモデルを完全再取得"
                affirmativeTitle = "完全再取得を開始"
            }
            repository = confirmation.repository
            revision = confirmation.revision
            license = confirmation.license
            totalByteCount = confirmation.totalByteCount
            sourceHost = confirmation.sourceHost
            assets = confirmation.assets
                .sorted {
                    Self.assetSortOrder($0.kind) < Self.assetSortOrder($1.kind)
                }
                .map {
                    Asset(
                        kind: $0.kind,
                        fileName: $0.fileName,
                        byteCount: $0.byteCount,
                        sha256: $0.sha256,
                        stableDownloadURL: $0.stableDownloadURL
                    )
                }
            networkNotice = "肯定ボタンを押すまでネットワーク通信は開始しません。押すと上記2資産の取得を開始します。"
        }

        private static func assetSortOrder(_ kind: StemModelAssetKind) -> Int {
            switch kind {
            case .modelWeights: 0
            case .modelConfiguration: 1
            case .metalLibrary: 2
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
                help = "取得内容の確認画面を開きます。承認するまで通信しません。"
                isPrimary = true
            case .repair:
                title = "AIモデルを修復"
                systemImage = "wrench.and.screwdriver"
                help = "欠落・破損状態を直すため、AIモデル2資産の取得確認を開きます。"
                isPrimary = true
            case .redownload:
                title = "モデル再取得"
                systemImage = "arrow.clockwise.circle"
                help = "AIモデル2資産を完全再取得する確認画面を開きます。"
                isPrimary = false
            case .revalidate:
                title = "モデル検証"
                systemImage = "checkmark.shield"
                help = "ネットワークを使わず、ローカル資産をもう一度検証します。"
                isPrimary = false
            }
        }
    }
}

private extension StemModelManagementSection {
    struct ProgressContext {
        let presentation: ProgressPresentation
        let isCancelling: Bool
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
                        "再検証しても解消しない場合は、アプリを正規配布物から再インストールしてください。AIモデルの再取得では直りません。",
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

    struct AcquisitionProgressCard: View {
        let presentation: ProgressPresentation
        let isCancelling: Bool
        let onCancel: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Label(presentation.stageTitle, systemImage: stageSymbol)
                    .font(.headline)
                Text(presentation.stageDetail)
                    .font(.body)
                    .foregroundStyle(.secondary)

                ProgressRow(
                    title: "全体",
                    fraction: presentation.overallFraction,
                    receivedBytes: presentation.receivedBytes,
                    totalBytes: presentation.totalBytes,
                    accessibilityLabel: "AIモデル取得の全体進捗"
                )

                ForEach(presentation.assetProgresses) { asset in
                    ProgressRow(
                        title: progressTitle(for: asset),
                        fraction: asset.fraction,
                        receivedBytes: asset.receivedBytes,
                        totalBytes: asset.totalBytes,
                        accessibilityLabel: "\(asset.fileName)の取得進捗"
                    )
                }

                if presentation.isWaitingForConnectivity {
                    Label("オフラインまたは接続待機中です", systemImage: "wifi.slash")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if presentation.canRequestCancellation {
                    HStack {
                        Spacer()
                        Button(
                            "取得を中断",
                            systemImage: "stop.circle",
                            role: .cancel,
                            action: onCancel
                        )
                        .keyboardShortcut(.cancelAction)
                        .help("取得途中のstagingを破棄し、検証済みactive世代は維持します。")
                    }
                } else if !isCancelling && presentation.phase == .activating {
                    Label(
                        "active世代の有効化中は中断できません",
                        systemImage: "lock.shield"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .velouraAdaptiveGlass(in: .rect(cornerRadius: 16))
        }

        private var stageSymbol: String {
            if isCancelling {
                "stop.circle"
            } else if presentation.isWaitingForConnectivity {
                "wifi.slash"
            } else {
                switch presentation.phase {
                case .preparing: "shippingbox"
                case .downloading: "arrow.down.circle"
                case .validating: "checkmark.shield"
                case .activating: "lock.shield"
                case .completed: "checkmark.seal"
                }
            }
        }

        private func progressTitle(
            for asset: ProgressPresentation.AssetProgress
        ) -> String {
            if asset.isCurrent && presentation.phase == .downloading {
                "\(asset.fileName)（取得中）"
            } else {
                asset.fileName
            }
        }
    }

    struct ProgressRow: View {
        let title: String
        let fraction: Double
        let receivedBytes: Int64
        let totalBytes: Int64
        let accessibilityLabel: String

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent(title) {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                ProgressView(value: fraction)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityValue(
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                    )
                Text("\(receivedBytes) / \(totalBytes) bytes")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    struct RecoveryFailureCard: View {
        let message: String
        let onDismiss: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Label("モデル操作に失敗しました", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(message)
                    .font(.body)
                    .textSelection(.enabled)
                Text("既存の検証済みactive世代がある場合は維持され、失敗したstagingをactiveへ切り替えません。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("エラーを閉じる", action: onDismiss)
                }
            }
            .padding(16)
            .background(.red.opacity(0.08), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.red.opacity(0.35))
                    .allowsHitTesting(false)
            }
        }
    }

    struct RecoveryActionSection: View {
        let actions: [StemModelRecoveryAction]
        let isDisabled: Bool
        let onAction: (StemModelRecoveryAction) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("選択できる操作")
                    .font(.headline)

                HStack(spacing: 10) {
                    ForEach(actions) { action in
                        RecoveryActionButton(
                            presentation: ActionPresentation(action: action),
                            action: { onAction(action) }
                        )
                    }
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

    struct ModelDownloadConfirmationSheet: View {
        let errorMessage: String?
        let onConfirm: () -> Void
        let onCancel: () -> Void

        private let presentation: DownloadConfirmationPresentation

        init(
            confirmation: StemModelDownloadConfirmation,
            errorMessage: String?,
            onConfirm: @escaping () -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.errorMessage = errorMessage
            self.onConfirm = onConfirm
            self.onCancel = onCancel
            self.presentation = DownloadConfirmationPresentation(
                confirmation: confirmation
            )
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(presentation.title)
                        .font(.title2.bold())
                    Text("固定Revisionから取得する2資産を確認してください。取得後は容量・Revision・SHA-256を検証してから有効化します。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        DownloadContractCard(presentation: presentation)

                        ForEach(presentation.assets) { asset in
                            DownloadAssetCard(asset: asset)
                        }

                        Label(presentation.networkNotice, systemImage: "network")
                            .font(.callout)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.1), in: .rect(cornerRadius: 12))

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.red.opacity(0.08), in: .rect(cornerRadius: 12))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollContentBackground(.hidden)

                Divider()

                HStack {
                    Button("戻る", role: .cancel, action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(
                        presentation.affirmativeTitle,
                        systemImage: "arrow.down.circle",
                        action: onConfirm
                    )
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("表示中の2資産についてネットワーク取得を開始します。")
                }
            }
            .padding(20)
            .frame(minWidth: 640, idealWidth: 720, minHeight: 540, idealHeight: 680)
        }
    }

    struct DownloadContractCard: View {
        let presentation: DownloadConfirmationPresentation

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("取得契約")
                    .font(.headline)
                contractValue(label: "取得元", value: presentation.repository)
                contractValue(label: "固定Revision", value: presentation.revision)
                contractValue(label: "License", value: presentation.license)
                contractValue(
                    label: "合計容量",
                    value: "\(presentation.totalByteCount) bytes"
                )
                if let sourceHost = presentation.sourceHost {
                    contractValue(label: "通信先ホスト", value: sourceHost)
                }
            }
            .padding(14)
            .velouraAdaptiveGlass(in: .rect(cornerRadius: 14))
        }

        private func contractValue(label: String, value: String) -> some View {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    struct DownloadAssetCard: View {
        let asset: DownloadConfirmationPresentation.Asset

        var body: some View {
            VStack(alignment: .leading, spacing: 9) {
                Label(asset.fileName, systemImage: "doc")
                    .font(.headline)
                assetValue(label: "容量", value: "\(asset.byteCount) bytes")
                assetValue(label: "SHA-256", value: asset.sha256)
                assetValue(label: "固定配布URL", value: asset.stableDownloadURL)
            }
            .padding(14)
            .background(.regularMaterial, in: .rect(cornerRadius: 14))
        }

        private func assetValue(label: String, value: String) -> some View {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
