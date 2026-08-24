import SwiftUI

enum WorkspaceLayoutMetrics {
    static let sidebarMinimumWidth: CGFloat = 220
    static let sidebarIdealWidth: CGFloat = 260
    static let sidebarMaximumWidth: CGFloat = 300
    static let minimumCenterWidth: CGFloat = 680
    static let inspectorWidth: CGFloat = 480
    static let inspectorVisibleMinimumWindowWidth: CGFloat = 1_500
    static let inspectorHiddenMinimumWindowWidth: CGFloat = 1_500
    static let minimumWindowHeight: CGFloat = 720
    static let recentLogMinimumWidth: CGFloat = 260
    static let standardWorkflowMinimumWidth: CGFloat = 260
    static let expandedWorkflowMinimumWidth: CGFloat = 360
    static let bottomRegionMinimumHeight: CGFloat = 206
    static let bottomRegionIdealHeight: CGFloat = 214
    static let bottomRegionMaximumHeight: CGFloat = 224

    static func workflowMinimumWidth(stageCount: Int) -> CGFloat {
        stageCount > 4
            ? expandedWorkflowMinimumWidth
            : standardWorkflowMinimumWidth
    }
}

struct WorkspaceShellView<
    Sidebar: View,
    Center: View,
    Inspector: View
>: View {
    @Binding var sidebarVisibility: NavigationSplitViewVisibility
    @State private var bottomRegionHeight =
        WorkspaceLayoutMetrics.bottomRegionIdealHeight
    let isInspectorPresented: Bool
    let sidebar: Sidebar
    let center: Center
    let inspector: Inspector

    init(
        sidebarVisibility: Binding<NavigationSplitViewVisibility>,
        isInspectorPresented: Bool,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder center: () -> Center,
        @ViewBuilder inspector: () -> Inspector
    ) {
        _sidebarVisibility = sidebarVisibility
        self.isInspectorPresented = isInspectorPresented
        self.sidebar = sidebar()
        self.center = center()
        self.inspector = inspector()
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: WorkspaceLayoutMetrics.sidebarMinimumWidth,
                    ideal: WorkspaceLayoutMetrics.sidebarIdealWidth,
                    max: WorkspaceLayoutMetrics.sidebarMaximumWidth
                )
        } detail: {
            HStack(spacing: 0) {
                center
                    .frame(
                        minWidth: WorkspaceLayoutMetrics.minimumCenterWidth,
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                    .zIndex(1)

                inspector
                    .contentMargins(
                        .bottom,
                        bottomRegionHeight,
                        for: .scrollContent
                    )
                    .frame(
                        minWidth: WorkspaceLayoutMetrics.inspectorWidth,
                        idealWidth: WorkspaceLayoutMetrics.inspectorWidth,
                        maxWidth: WorkspaceLayoutMetrics.inspectorWidth,
                        maxHeight: .infinity
                    )
                    .mask(alignment: .top) {
                        Rectangle()
                            .padding(.bottom, bottomRegionHeight)
                    }
                    .frame(
                        width: isInspectorPresented
                            ? WorkspaceLayoutMetrics.inspectorWidth
                            : 0,
                        alignment: .trailing
                    )
                    .clipped()
                    .overlay(alignment: .leading) {
                        Divider()
                            .padding(.bottom, bottomRegionHeight)
                    }
                    .opacity(isInspectorPresented ? 1 : 0)
                    .allowsHitTesting(isInspectorPresented)
                    .accessibilityHidden(!isInspectorPresented)
                    .zIndex(0)
            }
            .onPreferenceChange(WorkspaceBottomRegionHeightPreferenceKey.self) { height in
                guard abs(bottomRegionHeight - height) > 0.5 else { return }
                bottomRegionHeight = height
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .toolbar(removing: .sidebarToggle)
    }
}

struct WorkspaceCenterLayout<
    Header: View,
    MainContent: View,
    Footer: View,
    AnalysisPanel: View,
    FullLog: View
>: View {
    let isFullLogPresented: Bool
    let bottomRegionTrailingExtension: CGFloat
    let header: Header
    let mainContent: MainContent
    let footer: Footer
    let analysisPanel: AnalysisPanel
    let fullLog: FullLog

    init(
        isFullLogPresented: Bool,
        bottomRegionTrailingExtension: CGFloat,
        @ViewBuilder header: () -> Header,
        @ViewBuilder mainContent: () -> MainContent,
        @ViewBuilder footer: () -> Footer,
        @ViewBuilder analysisPanel: () -> AnalysisPanel,
        @ViewBuilder fullLog: () -> FullLog
    ) {
        self.isFullLogPresented = isFullLogPresented
        self.bottomRegionTrailingExtension = bottomRegionTrailingExtension
        self.header = header()
        self.mainContent = mainContent()
        self.footer = footer()
        self.analysisPanel = analysisPanel()
        self.fullLog = fullLog()
    }

    var body: some View {
        VStack(spacing: 0) {
            if isFullLogPresented {
                fullLog
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
            } else {
                header

                ScrollView {
                    mainContent
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                        .velouraTransientOverlayScrollIndicators()
                }
                .scrollContentBackground(.hidden)
                .scrollEdgeEffectStyle(.soft, for: .top)

                Divider()
                    .padding(.trailing, -bottomRegionTrailingExtension)
                HStack(alignment: .top, spacing: 0) {
                    footer
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    analysisPanel
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .frame(
                            width: WorkspaceLayoutMetrics.inspectorWidth,
                            alignment: .topLeading
                        )
                        .frame(
                            minHeight: WorkspaceLayoutMetrics.bottomRegionMinimumHeight,
                            idealHeight: WorkspaceLayoutMetrics.bottomRegionIdealHeight,
                            maxHeight: WorkspaceLayoutMetrics.bottomRegionMaximumHeight,
                            alignment: .topLeading
                        )
                }
                .padding(.trailing, -bottomRegionTrailingExtension)
                .background {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .preference(
                                key: WorkspaceBottomRegionHeightPreferenceKey.self,
                                value: geometry.size.height
                            )
                    }
                }
            }
        }
    }
}

private struct WorkspaceBottomRegionHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct WorkspaceFixedHeaderView<DisplayPicker: View>: View {
    let title: String
    let summary: String
    let displayPicker: DisplayPicker

    init(
        title: String,
        summary: String,
        @ViewBuilder displayPicker: () -> DisplayPicker
    ) {
        self.title = title
        self.summary = summary
        self.displayPicker = displayPicker()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.bold())
            Text(summary)
                .foregroundStyle(.secondary)

            displayPicker
                .padding(.top, 10)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkspaceLazySection<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            content
        }
    }
}

struct WorkspaceFooterLayout: View {
    let events: [RecentActivityEvent]
    let stages: [WorkspaceFooterStage]
    let fullLogHelp: String
    @Binding var isFullLogPresented: Bool

    var body: some View {
        let workflowMinimumWidth = WorkspaceLayoutMetrics.workflowMinimumWidth(
            stageCount: stages.count
        )

        HStack(alignment: .top, spacing: 22) {
            RecentProcessingLogView(
                events: events,
                fullLogHelp: fullLogHelp,
                isFullLogPresented: $isFullLogPresented
            )
            .padding(12)
            .velouraAdaptiveGlass(in: .rect(cornerRadius: 14))
            .frame(
                minWidth: WorkspaceLayoutMetrics.recentLogMinimumWidth,
                maxWidth: .infinity,
                alignment: .topLeading
            )

            OverallWorkflowView(stages: stages)
                .padding(12)
                .velouraAdaptiveGlass(in: .rect(cornerRadius: 14))
                .frame(
                    minWidth: workflowMinimumWidth,
                    idealWidth: max(320, workflowMinimumWidth),
                    maxWidth: 360,
                    alignment: .topLeading
                )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(
            minHeight: 206,
            idealHeight: 214,
            maxHeight: 224,
            alignment: .top
        )
    }
}
