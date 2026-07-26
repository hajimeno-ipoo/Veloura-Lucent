import Foundation
import Testing
import UserNotifications
@testable import VelouraLucent

@MainActor
struct StemCompletionNotificationServiceTests {
    final class NotificationCenterSpy: UserNotificationCenterProviding {
        var addedRequests: [UNNotificationRequest] = []
        var addCompletionHandlerWasProvided = false

        func requestAuthorization(
            options: UNAuthorizationOptions,
            completionHandler: @escaping @Sendable (Bool, (any Error)?) -> Void
        ) {
            completionHandler(true, nil)
        }

        func add(
            _ request: UNNotificationRequest,
            withCompletionHandler completionHandler: (@Sendable ((any Error)?) -> Void)?
        ) {
            addedRequests.append(request)
            addCompletionHandlerWasProvided = completionHandler != nil
            completionHandler?(nil)
        }
    }

    final class PreferencesStub: CompletionNotificationPreferenceProviding {
        var completionNotificationsEnabled: Bool

        init(completionNotificationsEnabled: Bool) {
            self.completionNotificationsEnabled = completionNotificationsEnabled
        }
    }

    @Test
    func disabledPreferenceDoesNotRegisterStemNotification() {
        let notificationCenter = NotificationCenterSpy()
        let service = StemCompletionNotificationService(
            notificationCenter: notificationCenter,
            preferences: PreferencesStub(completionNotificationsEnabled: false)
        )

        service.notifyStemCompletion(for: .correction)

        #expect(notificationCenter.addedRequests.isEmpty)
    }

    @Test("補正完了とマスタリング完了を別のStem専用通知として登録する", arguments: StemCompletionNotificationStage.allCases)
    func enabledPreferenceRegistersDedicatedStemNotification(
        stage: StemCompletionNotificationStage
    ) throws {
        let notificationCenter = NotificationCenterSpy()
        let service = StemCompletionNotificationService(
            notificationCenter: notificationCenter,
            preferences: PreferencesStub(completionNotificationsEnabled: true)
        )

        service.notifyStemCompletion(for: stage)

        let request = try #require(notificationCenter.addedRequests.first)
        #expect(notificationCenter.addedRequests.count == 1)
        #expect(notificationCenter.addCompletionHandlerWasProvided)
        #expect(request.identifier.hasPrefix("veloura-lucent-stem-\(stage.rawValue)-"))
        #expect(request.content.title == stage.title)
        #expect(request.content.body == stage.body)
        #expect(request.content.sound != nil)
    }
}
