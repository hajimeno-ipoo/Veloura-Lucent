import Accessibility

enum AccessibilityAnnouncementService {
    @MainActor
    static func post(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}
