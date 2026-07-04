import SwiftUI

enum LiquidGlassMotion {
    static let selection = Animation.easeInOut(duration: 0.22)
    static let panel = Animation.easeInOut(duration: 0.24)

    @MainActor
    static func perform(
        reduceMotion: Bool,
        animation: Animation,
        _ changes: () -> Void
    ) {
        if reduceMotion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                changes()
            }
        } else {
            withAnimation(animation) {
                changes()
            }
        }
    }
}
