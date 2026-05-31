import Foundation
import UserNotifications

enum CompletionNotificationDomain: String, Sendable, Equatable {
    case correction
    case mastering

    var notificationTitle: String {
        switch self {
        case .correction:
            return "補正が完了しました"
        case .mastering:
            return "マスタリングが完了しました"
        }
    }
}

@MainActor
protocol CompletionNotificationReporting: AnyObject {
    func requestAuthorization()
    func notifyCompletion(for domain: CompletionNotificationDomain)
}

@MainActor
final class NoOpCompletionNotificationReporter: CompletionNotificationReporting {
    static let shared = NoOpCompletionNotificationReporter()

    private init() {}

    func requestAuthorization() {}
    func notifyCompletion(for domain: CompletionNotificationDomain) {}
}

@MainActor
final class NotificationService: CompletionNotificationReporting {
    static let shared = NotificationService()

    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyCompletion(for domain: CompletionNotificationDomain) {
        let content = UNMutableNotificationContent()
        content.title = domain.notificationTitle
        content.body = "Veloura Lucentでの処理が完了しました。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "veloura-lucent-\(domain.rawValue)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
