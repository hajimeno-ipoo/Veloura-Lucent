import Foundation
import Testing
import UserNotifications
@testable import VelouraLucent

@MainActor
struct NotificationServiceTests {
    final class NotificationCenterSpy: UserNotificationCenterProviding {
        var authorizationRequestCount = 0
        var authorizationOptions: UNAuthorizationOptions?
        var addedRequests: [UNNotificationRequest] = []
        var addCompletionHandlerWasProvided = false
        var addError: Error?

        func requestAuthorization(
            options: UNAuthorizationOptions,
            completionHandler: @escaping @Sendable (Bool, Error?) -> Void
        ) {
            authorizationRequestCount += 1
            authorizationOptions = options
            completionHandler(true, nil)
        }

        func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?) {
            addedRequests.append(request)
            addCompletionHandlerWasProvided = completionHandler != nil
            completionHandler?(addError)
        }
    }

    final class PreferencesStub: CompletionNotificationPreferenceProviding {
        var completionNotificationsEnabled: Bool

        init(completionNotificationsEnabled: Bool) {
            self.completionNotificationsEnabled = completionNotificationsEnabled
        }
    }

    @Test
    func disabledCompletionNotificationsDoNotRequestAuthorization() {
        let notificationCenter = NotificationCenterSpy()
        let service = NotificationService(
            notificationCenter: notificationCenter,
            preferences: PreferencesStub(completionNotificationsEnabled: false)
        )

        service.requestAuthorization()

        #expect(notificationCenter.authorizationRequestCount == 0)
    }

    @Test
    func userDefaultsPreferencesDefaultToEnabled() {
        let suiteName = "NotificationServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = UserDefaultsCompletionNotificationPreferences(defaults: defaults)

        #expect(preferences.completionNotificationsEnabled)
    }

    @Test
    func enabledCompletionNotificationsRequestAlertAndSoundAuthorization() {
        let notificationCenter = NotificationCenterSpy()
        let service = NotificationService(
            notificationCenter: notificationCenter,
            preferences: PreferencesStub(completionNotificationsEnabled: true)
        )

        service.requestAuthorization()

        #expect(notificationCenter.authorizationRequestCount == 1)
        #expect(notificationCenter.authorizationOptions?.contains(.alert) == true)
        #expect(notificationCenter.authorizationOptions?.contains(.sound) == true)
    }

    @Test
    func disabledCompletionNotificationsDoNotRegisterNotification() {
        let notificationCenter = NotificationCenterSpy()
        let service = NotificationService(
            notificationCenter: notificationCenter,
            preferences: PreferencesStub(completionNotificationsEnabled: false)
        )

        service.notifyCompletion(for: .correction)

        #expect(notificationCenter.addedRequests.isEmpty)
    }

    @Test
    func enabledCompletionNotificationsRegisterCompletionNotification() {
        let notificationCenter = NotificationCenterSpy()
        let service = NotificationService(
            notificationCenter: notificationCenter,
            preferences: PreferencesStub(completionNotificationsEnabled: true)
        )

        service.notifyCompletion(for: .mastering)

        #expect(notificationCenter.addedRequests.count == 1)
        #expect(notificationCenter.addCompletionHandlerWasProvided)
        #expect(notificationCenter.addedRequests.first?.content.title == "マスタリングが完了しました")
        #expect(notificationCenter.addedRequests.first?.content.body == "Veloura Lucentでの処理が完了しました。")
        #expect(notificationCenter.addedRequests.first?.content.sound != nil)
    }

    @Test
    func addFailureStillUsesCompletionHandlerPath() {
        let notificationCenter = NotificationCenterSpy()
        notificationCenter.addError = NSError(domain: "NotificationServiceTests", code: 1)
        let service = NotificationService(
            notificationCenter: notificationCenter,
            preferences: PreferencesStub(completionNotificationsEnabled: true)
        )

        service.notifyCompletion(for: .correction)

        #expect(notificationCenter.addedRequests.count == 1)
        #expect(notificationCenter.addCompletionHandlerWasProvided)
    }
}
