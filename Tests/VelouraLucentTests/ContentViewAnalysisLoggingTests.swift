import Foundation
import Testing
@testable import VelouraLucent

struct ContentViewAnalysisLoggingTests {
    @Test
    @MainActor
    func inspectorWindowMinimumWidthsMatchLayoutContract() {
        #expect(WorkspaceLayoutMetrics.sidebarMinimumWidth == 220)
        #expect(WorkspaceLayoutMetrics.sidebarIdealWidth == 260)
        #expect(WorkspaceLayoutMetrics.sidebarMaximumWidth == 300)
        #expect(WorkspaceLayoutMetrics.minimumCenterWidth == 680)
        #expect(WorkspaceLayoutMetrics.inspectorWidth == 480)
        #expect(WorkspaceLayoutMetrics.inspectorVisibleMinimumWindowWidth == 1_500)
        #expect(WorkspaceLayoutMetrics.inspectorHiddenMinimumWindowWidth == 1_500)
        #expect(WorkspaceLayoutMetrics.minimumWindowHeight == 720)
        #expect(WorkspaceLayoutMetrics.recentLogMinimumWidth == 260)
        #expect(WorkspaceLayoutMetrics.workflowMinimumWidth(stageCount: 4) == 260)
        #expect(WorkspaceLayoutMetrics.workflowMinimumWidth(stageCount: 5) == 360)
        #expect(
            WorkspaceLayoutMetrics.recentLogMinimumWidth
                + 22
                + WorkspaceLayoutMetrics.workflowMinimumWidth(stageCount: 5)
                + 36
                <= WorkspaceLayoutMetrics.minimumCenterWidth
        )
        #expect(
            WorkspaceLayoutMetrics.sidebarMaximumWidth
                + WorkspaceLayoutMetrics.minimumCenterWidth
                + WorkspaceLayoutMetrics.inspectorWidth
                < WorkspaceLayoutMetrics.inspectorVisibleMinimumWindowWidth
        )
        #expect(
            WorkspaceLayoutMetrics.sidebarMaximumWidth
                + WorkspaceLayoutMetrics.minimumCenterWidth
                + WorkspaceLayoutMetrics.inspectorWidth
                < WorkspaceLayoutMetrics.inspectorHiddenMinimumWindowWidth
        )
    }

    @Test
    func displayAnalysisMeasurementLogsDuration() async throws {
        let logs = ThreadSafeLogCollector()

        let value = try await DisplayAnalysisSupport.measure("ノイズ測定", logHandler: { message in
            logs.append(message)
        }) {
            42
        }

        #expect(value == 42)
        #expect(logs.values.count == 1)
        #expect(logs.values.first?.hasPrefix("表示解析/計測: ノイズ測定: ") == true)
        #expect(logs.values.first?.hasSuffix("秒") == true)
    }

    @Test
    func disabledOptionalDisplayAnalysisDoesNotLog() async throws {
        let logs = ThreadSafeLogCollector()

        let value: Int? = try await DisplayAnalysisSupport.measureOptional("プレビュー生成", isEnabled: false, logHandler: { message in
            logs.append(message)
        }) {
            Issue.record("Disabled display analysis work should not run")
            return 42
        }

        #expect(value == nil)
        #expect(logs.values.isEmpty)
    }
}

private final class ThreadSafeLogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(message)
    }
}
