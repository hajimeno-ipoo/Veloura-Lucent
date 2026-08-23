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

enum CompletionNotificationItem: String, CaseIterable, Identifiable, Sendable {
    case standardCorrection
    case standardMastering
    case stemCorrection
    case stemMastering

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standardCorrection:
            "通常補正"
        case .standardMastering:
            "通常マスタリング"
        case .stemCorrection:
            "Stem Mode補正"
        case .stemMastering:
            "Stem Modeマスタリング"
        }
    }
}

enum CompletionNotificationAuthorizationStatus: Sendable, Equatable {
    case unknown
    case notDetermined
    case denied
    case authorized

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized, .provisional, .ephemeral:
            self = .authorized
        @unknown default:
            self = .unknown
        }
    }

    var title: String {
        switch self {
        case .unknown:
            "確認中"
        case .notDetermined:
            "未確認"
        case .denied:
            "未許可"
        case .authorized:
            "許可済み"
        }
    }
}

@MainActor
protocol CompletionNotificationReporting: AnyObject {
    func authorizationStatus() async -> CompletionNotificationAuthorizationStatus
    func requestAuthorization() async -> Bool
    func notifyCompletion(for domain: CompletionNotificationDomain)
}

@MainActor
protocol CompletionNotificationPreferenceProviding: AnyObject {
    var completionNotificationsEnabled: Bool { get set }
    func isEnabled(for item: CompletionNotificationItem) -> Bool
    func setEnabled(_ isEnabled: Bool, for item: CompletionNotificationItem)
}

@MainActor
final class UserDefaultsCompletionNotificationPreferences: CompletionNotificationPreferenceProviding {
    static let shared = UserDefaultsCompletionNotificationPreferences()
    static let completionNotificationsEnabledKey = "completionNotificationsEnabled"
    private static let itemKeyPrefix = "completionNotificationItemEnabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var completionNotificationsEnabled: Bool {
        get {
            defaults.object(forKey: Self.completionNotificationsEnabledKey) as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: Self.completionNotificationsEnabledKey)
        }
    }

    func isEnabled(for item: CompletionNotificationItem) -> Bool {
        let key = itemKey(for: item)
        return defaults.object(forKey: key) as? Bool ?? true
    }

    func setEnabled(_ isEnabled: Bool, for item: CompletionNotificationItem) {
        defaults.set(isEnabled, forKey: itemKey(for: item))
    }

    private func itemKey(for item: CompletionNotificationItem) -> String {
        "\(Self.itemKeyPrefix).\(item.rawValue)"
    }
}

@MainActor
protocol UserNotificationCenterProviding: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?)
}

extension UNUserNotificationCenter: UserNotificationCenterProviding {
    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await notificationSettings()
        return settings.authorizationStatus
    }
}

@MainActor
final class NoOpCompletionNotificationReporter: CompletionNotificationReporting {
    static let shared = NoOpCompletionNotificationReporter()

    private init() {}

    func authorizationStatus() async -> CompletionNotificationAuthorizationStatus { .unknown }
    func requestAuthorization() async -> Bool { false }
    func notifyCompletion(for domain: CompletionNotificationDomain) {}
}

@MainActor
final class NotificationService: CompletionNotificationReporting {
    static let shared: CompletionNotificationReporting = makeSharedReporter()

    private let notificationCenter: UserNotificationCenterProviding
    private let preferences: CompletionNotificationPreferenceProviding
    private let logger: Logger

    private static func makeSharedReporter() -> CompletionNotificationReporting {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return NoOpCompletionNotificationReporter.shared
        }

        return NotificationService(notificationCenter: UNUserNotificationCenter.current())
    }

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

    func authorizationStatus() async -> CompletionNotificationAuthorizationStatus {
        CompletionNotificationAuthorizationStatus(await notificationCenter.authorizationStatus())
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await notificationCenter.requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("Failed to request notification authorization: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func notifyCompletion(for domain: CompletionNotificationDomain) {
        guard preferences.completionNotificationsEnabled else { return }
        guard preferences.isEnabled(for: domain.notificationItem) else { return }

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

private extension CompletionNotificationDomain {
    var notificationItem: CompletionNotificationItem {
        switch self {
        case .correction:
            .standardCorrection
        case .mastering:
            .standardMastering
        }
    }
}
