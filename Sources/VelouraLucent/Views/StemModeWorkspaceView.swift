import SwiftUI

@MainActor
struct StemModeWorkspaceView: View {
    @Bindable var model: StemModeWorkspaceModel
    let footerTrailingInset: CGFloat

    @State private var isFullLogPresented = false
    @State private var inputAudioDropVisualState: InputAudioDropVisualState = .inactive

    var body: some View {
        ZStack {
            StemModeMainWorkspaceView(
                model: model,
                isFullLogPresented: $isFullLogPresented,
                footerTrailingInset: footerTrailingInset
            )

            InputAudioDropReceiver(
                isEnabled: model.canChooseInput,
                visualState: $inputAudioDropVisualState,
                onDrop: acceptDroppedInput
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)

            switch inputAudioDropVisualState {
            case .inactive:
                EmptyView()
            case .accepted:
                InputAudioDropOverlay(kind: .accepted)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            case .rejected:
                InputAudioDropOverlay(kind: .rejected)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .alert(item: $model.presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("閉じる"))
            )
        }
    }

    private func acceptDroppedInput(_ URLs: [URL]) -> Bool {
        guard model.canChooseInput, let URL = URLs.first else { return false }
        Task { await model.inspectInput(URL) }
        return true
    }

}

@MainActor
struct StemModeMainWorkspaceView: View {
    @Bindable var model: StemModeWorkspaceModel
    @Binding var isFullLogPresented: Bool
    let footerTrailingInset: CGFloat
    @State private var selectedMode: WorkspaceDisplayMode = .basic

    private enum WorkspaceDisplayMode: String, CaseIterable, Identifiable {
        case basic
        case detail

        var id: String { rawValue }
        var title: String { self == .basic ? "基本表示" : "詳細解析" }
    }

    var body: some View {
        WorkspaceCenterLayout(
            isFullLogPresented: isFullLogPresented,
            footerTrailingInset: footerTrailingInset
        ) {
            fixedHeader
        } mainContent: {
            switch selectedMode {
            case .basic:
                StemModePreviewView(model: model)
            case .detail:
                StemModeDetailedAnalysisWorkspaceView(model: model)
            }
        } footer: {
            StemModeFooterView(
                model: model,
                isFullLogPresented: $isFullLogPresented
            )
        } fullLog: {
            StemModeFullProcessingLogView(
                session: model.session,
                onDismiss: { isFullLogPresented = false }
            )
        }
        .focusedSceneValue(
            \.velouraWorkspaceDisplaySelection,
            workspaceDisplaySelection
        )
    }

    private var workspaceDisplaySelection: Binding<VelouraWorkspaceDisplaySelection> {
        Binding(
            get: {
                if isFullLogPresented { return .fullLog }
                return selectedMode == .basic ? .basic : .detailedAnalysis
            },
            set: { selection in
                switch selection {
                case .basic:
                    isFullLogPresented = false
                    selectedMode = .basic
                case .detailedAnalysis:
                    isFullLogPresented = false
                    selectedMode = .detail
                case .fullLog:
                    isFullLogPresented = true
                }
            }
        )
    }

    private var fixedHeader: some View {
        WorkspaceFixedHeaderView(
            title: "Veloura Lucent — Stem Mode",
            summary: "4／6Stem分離・Stem別補正を基準に、再ミックスと既存マスタリングを独立して実行します"
        ) {
            LiquidGlassSegmentedPicker(
                title: "中央表示",
                options: WorkspaceDisplayMode.allCases,
                selection: $selectedMode,
                label: \.title
            )
        }
    }
}
