import Foundation
import Testing
import UserNotifications
@testable import VelouraLucent

@MainActor
struct NotificationServiceTests {
    final class NotificationCenterSpy: UserNotificationCenterProviding {
        var authorizationRequestCount = 0
        var authorizationOptions: UNAuthorizationOptions?
        var currentAuthorizationStatus: UNAuthorizationStatus = .authorized
        var addedRequests: [UNNotificationRequest] = []
        var addCompletionHandlerWasProvided = false
        var addError: Error?

        func authorizationStatus() async -> UNAuthorizationStatus {
            currentAuthorizationStatus
        }

        func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
            authorizationRequestCount += 1
            authorizationOptions = options
            return true
        }

        func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?) {
            addedRequests.append(request)
            addCompletionHandlerWasProvided = completionHandler != nil
            completionHandler?(addError)
        }
    }

    final class PreferencesStub: CompletionNotificationPreferenceProviding {
        var completionNotificationsEnabled: Bool
        var disabledItems: Set<CompletionNotificationItem>

        init(
            completionNotificationsEnabled: Bool,
            disabledItems: Set<CompletionNotificationItem> = []
        ) {
            self.completionNotificationsEnabled = completionNotificationsEnabled
            self.disabledItems = disabledItems
        }

        func isEnabled(for item: CompletionNotificationItem) -> Bool {
            !disabledItems.contains(item)
        }

        func setEnabled(_ isEnabled: Bool, for item: CompletionNotificationItem) {
            if isEnabled {
                disabledItems.remove(item)
            } else {
                disabledItems.insert(item)
            }
        }
    }

    @Test
    func authorizationRequestIsIndependentFromAppNotificationPreference() async {
        let notificationCenter = NotificationCenterSpy()
        let service = NotificationService(
            notificationCenter: notificationCenter,
            preferences: PreferencesStub(completionNotificationsEnabled: false)
        )

        let isAuthorized = await service.requestAuthorization()

        #expect(isAuthorized)
        #expect(notificationCenter.authorizationRequestCount == 1)
    }

    @Test
    func userDefaultsPreferencesDefaultToDisabledUntilUserOptsIn() {
        let suiteName = "NotificationServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = UserDefaultsCompletionNotificationPreferences(defaults: defaults)

        #expect(preferences.completionNotificationsEnabled == false)
        for item in CompletionNotificationItem.allCases {
            #expect(preferences.isEnabled(for: item))
        }
    }

    @Test
    func sharedReporterUsesNoOpOutsideAppBundle() {
        guard Bundle.main.bundleURL.pathExtension != "app" else { return }

        #expect(NotificationService.shared is NoOpCompletionNotificationReporter)
    }

    @Test
    func authorizationRequestUsesAlertAndSound() async {
        let notificationCenter = NotificationCenterSpy()
        let service = NotificationService(
            notificationCenter: notificationCenter,
            preferences: PreferencesStub(completionNotificationsEnabled: true)
        )

        let isAuthorized = await service.requestAuthorization()

        #expect(isAuthorized)
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
    func disabledStandardNotificationItemDoesNotRegisterNotification() {
        let notificationCenter = NotificationCenterSpy()
        let service = NotificationService(
            notificationCenter: notificationCenter,
            preferences: PreferencesStub(
                completionNotificationsEnabled: true,
                disabledItems: [.standardMastering]
            )
        )

        service.notifyCompletion(for: .mastering)

        #expect(notificationCenter.addedRequests.isEmpty)
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
