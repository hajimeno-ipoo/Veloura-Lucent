import Foundation
import OSLog
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
protocol CompletionNotificationPreferenceProviding: AnyObject {
    var completionNotificationsEnabled: Bool { get set }
}

@MainActor
final class UserDefaultsCompletionNotificationPreferences: CompletionNotificationPreferenceProviding {
    static let shared = UserDefaultsCompletionNotificationPreferences()
    static let completionNotificationsEnabledKey = "completionNotificationsEnabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var completionNotificationsEnabled: Bool {
        get {
            defaults.object(forKey: Self.completionNotificationsEnabledKey) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: Self.completionNotificationsEnabledKey)
        }
    }
}

protocol UserNotificationCenterProviding: AnyObject {
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, Error?) -> Void
    )
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?)
}

extension UNUserNotificationCenter: UserNotificationCenterProviding {}

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

    private let notificationCenter: UserNotificationCenterProviding
    private let preferences: CompletionNotificationPreferenceProviding
    private let logger: Logger

    init(
        notificationCenter: UserNotificationCenterProviding = UNUserNotificationCenter.current(),
        preferences: CompletionNotificationPreferenceProviding = UserDefaultsCompletionNotificationPreferences.shared,
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "VelouraLucent",
            category: "Notification"
        )
    ) {
        self.notificationCenter = notificationCenter
        self.preferences = preferences
        self.logger = logger
    }

    func requestAuthorization() {
        guard preferences.completionNotificationsEnabled else { return }

        notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyCompletion(for domain: CompletionNotificationDomain) {
        guard preferences.completionNotificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = domain.notificationTitle
        content.body = "Veloura Lucentでの処理が完了しました。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "veloura-lucent-\(domain.rawValue)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        notificationCenter.add(request) { [logger] error in
            if let error {
                logger.error("Failed to add completion notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
