import Foundation
import Testing
import UserNotifications
@testable import VelouraLucent

@MainActor
struct StemCompletionNotificationServiceTests {
    final class NotificationCenterSpy: UserNotificationCenterProviding {
        var addedRequests: [UNNotificationRequest] = []
        var addCompletionHandlerWasProvided = false

        func authorizationStatus() async -> UNAuthorizationStatus {
            .authorized
        }

        func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
            true
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
    func disabledPreferenceDoesNotRegisterStemNotification() {
        let notificationCenter = NotificationCenterSpy()
        let service = StemCompletionNotificationService(
            notificationCenter: notificationCenter,
            preferences: PreferencesStub(completionNotificationsEnabled: false)
        )

        service.notifyStemCompletion(
            for: .correction,
            runContract: makeStemTestRunContract()
        )

        #expect(notificationCenter.addedRequests.isEmpty)
    }

    @Test("補正完了とマスタリング完了をHT4／BS6の実行契約で別々に通知する")
    func enabledPreferenceRegistersRunContractSpecificStemNotifications() throws {
        for model in StemSeparationModel.allCases {
            let runContract = makeStemTestRunContract(model: model)
            for stage in StemCompletionNotificationStage.allCases {
                let notificationCenter = NotificationCenterSpy()
                let service = StemCompletionNotificationService(
                    notificationCenter: notificationCenter,
                    preferences: PreferencesStub(completionNotificationsEnabled: true)
                )

                service.notifyStemCompletion(
                    for: stage,
                    runContract: runContract
                )

                let request = try #require(notificationCenter.addedRequests.first)
                #expect(notificationCenter.addedRequests.count == 1)
                #expect(notificationCenter.addCompletionHandlerWasProvided)
                #expect(request.identifier.hasPrefix("veloura-lucent-stem-\(stage.rawValue)-"))
                #expect(request.content.title == stage.title)
                #expect(request.content.body == stage.body(runContract: runContract))
                #expect(request.content.body.contains(model.displayName))
                #expect(request.content.body.contains("\(runContract.stemCount)Stem"))
                #expect(request.content.sound != nil)
            }
        }
    }

    @Test
    func disabledStemNotificationItemDoesNotRegisterNotification() {
        let notificationCenter = NotificationCenterSpy()
        let service = StemCompletionNotificationService(
            notificationCenter: notificationCenter,
            preferences: PreferencesStub(
                completionNotificationsEnabled: true,
                disabledItems: [.stemCorrection]
            )
        )

        service.notifyStemCompletion(
            for: .correction,
            runContract: makeStemTestRunContract()
        )

        #expect(notificationCenter.addedRequests.isEmpty)
    }
}
