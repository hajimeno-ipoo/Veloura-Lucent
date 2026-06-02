import SwiftUI

struct AppSettingsPanel: View {
    private let preferences: CompletionNotificationPreferenceProviding
    private let notificationReporter: CompletionNotificationReporting
    @State private var completionNotificationsEnabled: Bool

    init(
        preferences: CompletionNotificationPreferenceProviding = UserDefaultsCompletionNotificationPreferences.shared,
        notificationReporter: CompletionNotificationReporting = NotificationService.shared
    ) {
        self.preferences = preferences
        self.notificationReporter = notificationReporter
        _completionNotificationsEnabled = State(initialValue: preferences.completionNotificationsEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("アプリ")
                .font(.headline)

            Toggle("完了通知", isOn: completionNotificationsBinding)
                .toggleStyle(.switch)
        }
    }

    private var completionNotificationsBinding: Binding<Bool> {
        Binding(
            get: { completionNotificationsEnabled },
            set: { newValue in
                completionNotificationsEnabled = newValue
                preferences.completionNotificationsEnabled = newValue
                if newValue {
                    notificationReporter.requestAuthorization()
                }
            }
        )
    }
}
