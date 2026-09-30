import Foundation
import OSLog
import UserNotifications

enum StemCompletionNotificationStage: String, CaseIterable, Equatable, Sendable {
    case correction
    case remix
    case mastering

    var title: String {
        switch self {
        case .correction:
            AppLanguageSettings.string("Stem Modeの補正が完了しました")
        case .remix:
            AppLanguageSettings.string("Stem Modeの再ミックスが完了しました")
        case .mastering:
            AppLanguageSettings.string("Stem Modeのマスタリングが完了しました")
        }
    }

    func body(runContract: StemModelRunContract) -> String {
        let modelName = runContract.separationModel.displayName
        return switch self {
        case .correction:
            String(
                format: AppLanguageSettings.string("%@の補正済み%ldStemを確認できます。再ミックスは別操作で開始してください。"),
                locale: AppLanguageSettings.locale,
                modelName,
                runContract.stemCount
            )
        case .remix:
            String(
                format: AppLanguageSettings.string("%@・%ldStemの再ミックス結果を確認できます。マスタリングは別操作で開始してください。"),
                locale: AppLanguageSettings.locale,
                modelName,
                runContract.stemCount
            )
        case .mastering:
            String(
                format: AppLanguageSettings.string("%@・%ldStemのStem Mode最終版を確認できます。"),
                locale: AppLanguageSettings.locale,
                modelName,
                runContract.stemCount
            )
        }
    }
}

@MainActor
protocol StemCompletionNotificationReporting: AnyObject {
    func notifyStemCompletion(
        for stage: StemCompletionNotificationStage,
        runContract: StemModelRunContract
    )
}

@MainActor
final class NoOpStemCompletionNotificationReporter: StemCompletionNotificationReporting {
    static let shared = NoOpStemCompletionNotificationReporter()

    private init() {}

    func notifyStemCompletion(
        for stage: StemCompletionNotificationStage,
        runContract: StemModelRunContract
    ) {}
}

/// Stem-only completion notification boundary.
///
/// It shares the user's app-level completion-notification preference and notification-center
/// transport, but it does not add a Stem case to Standard Mode's notification domain.
@MainActor
final class StemCompletionNotificationService: StemCompletionNotificationReporting {
    static let shared: any StemCompletionNotificationReporting = makeSharedReporter()

    private let notificationCenter: any UserNotificationCenterProviding
    private let preferences: any CompletionNotificationPreferenceProviding
    private let logger: Logger

    private static func makeSharedReporter() -> any StemCompletionNotificationReporting {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return NoOpStemCompletionNotificationReporter.shared
        }

        return StemCompletionNotificationService(
            notificationCenter: UNUserNotificationCenter.current()
        )
    }

    init(
        notificationCenter: any UserNotificationCenterProviding = UNUserNotificationCenter.current(),
        preferences: any CompletionNotificationPreferenceProviding = UserDefaultsCompletionNotificationPreferences.shared,
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "VelouraLucent",
            category: "StemNotification"
        )
    ) {
        self.notificationCenter = notificationCenter
        self.preferences = preferences
        self.logger = logger
    }

    func notifyStemCompletion(
        for stage: StemCompletionNotificationStage,
        runContract: StemModelRunContract
    ) {
        guard preferences.completionNotificationsEnabled else { return }
        guard preferences.isEnabled(for: stage.notificationItem) else { return }

        let content = UNMutableNotificationContent()
        content.title = stage.title
        content.body = stage.body(runContract: runContract)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "veloura-lucent-stem-\(stage.rawValue)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        notificationCenter.add(request) { [logger] error in
            if let error {
                logger.error(
                    "Failed to add Stem completion notification: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}

private extension StemCompletionNotificationStage {
    var notificationItem: CompletionNotificationItem {
        switch self {
        case .correction:
            .stemCorrection
        case .remix:
            .stemRemix
        case .mastering:
            .stemMastering
        }
    }
}
