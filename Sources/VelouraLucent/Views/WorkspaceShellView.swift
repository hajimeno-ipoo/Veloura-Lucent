import SwiftUI

enum WorkspaceLayoutMetrics {
    static let sidebarMinimumWidth: CGFloat = 220
    static let sidebarIdealWidth: CGFloat = 260
    static let sidebarMaximumWidth: CGFloat = 300
    static let minimumCenterWidth: CGFloat = 680
    static let inspectorWidth: CGFloat = 480
    static let inspectorVisibleMinimumWindowWidth: CGFloat = 1_500
    static let inspectorHiddenMinimumWindowWidth: CGFloat = 1_000
    static let minimumWindowHeight: CGFloat = 720
    static let recentLogMinimumWidth: CGFloat = 260
    static let standardWorkflowMinimumWidth: CGFloat = 260
    static let expandedWorkflowMinimumWidth: CGFloat = 360

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
    let isInspectorPresented: Bool
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let center: () -> Center
    @ViewBuilder let inspector: () -> Inspector

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebar()
                .navigationSplitViewColumnWidth(
                    min: WorkspaceLayoutMetrics.sidebarMinimumWidth,
                    ideal: WorkspaceLayoutMetrics.sidebarIdealWidth,
                    max: WorkspaceLayoutMetrics.sidebarMaximumWidth
                )
        } detail: {
            HStack(spacing: 0) {
                center()
                    .frame(
                        minWidth: WorkspaceLayoutMetrics.minimumCenterWidth,
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )

                if isInspectorPresented {
                    Divider()

                    inspector()
                        .frame(
                            minWidth: WorkspaceLayoutMetrics.inspectorWidth,
                            idealWidth: WorkspaceLayoutMetrics.inspectorWidth,
                            maxWidth: WorkspaceLayoutMetrics.inspectorWidth,
                            maxHeight: .infinity
                        )
                        .clipped()
                }
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
    FullLog: View
>: View {
    let isFullLogPresented: Bool
    @ViewBuilder let header: () -> Header
    @ViewBuilder let mainContent: () -> MainContent
    @ViewBuilder let footer: () -> Footer
    @ViewBuilder let fullLog: () -> FullLog

    var body: some View {
        VStack(spacing: 0) {
            if isFullLogPresented {
                fullLog()
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
            } else {
                header()

                ScrollView {
                    mainContent()
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                        .velouraTransientOverlayScrollIndicators()
                }
                .scrollContentBackground(.hidden)
                .scrollEdgeEffectStyle(.soft, for: .top)

                Divider()
                footer()
            }
        }
    }
}

struct WorkspaceFixedHeaderView<DisplayPicker: View>: View {
    let title: String
    let summary: String
    @ViewBuilder let displayPicker: () -> DisplayPicker

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.bold())
            Text(summary)
                .foregroundStyle(.secondary)

            displayPicker()
                .padding(.top, 10)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
