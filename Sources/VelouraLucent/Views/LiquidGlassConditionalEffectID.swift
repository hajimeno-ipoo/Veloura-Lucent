import SwiftUI

extension View {
    @ViewBuilder
    func liquidGlassEffectID(
        _ effectID: String,
        in namespace: Namespace.ID,
        isActive: Bool
    ) -> some View {
        if isActive {
            glassEffectID(effectID, in: namespace)
        } else {
            self
        }
    }
}
