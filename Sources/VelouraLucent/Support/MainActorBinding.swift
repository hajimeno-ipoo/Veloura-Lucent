import SwiftUI

/// Bridges MainActor-owned state into SwiftUI's Sendable `Binding` closures.
///
/// SwiftUI evaluates control bindings on the main actor. `assumeIsolated` keeps
/// that contract explicit and traps instead of silently touching UI state from
/// another executor if the framework contract is ever violated.
private struct MainActorBindingAccess<Value: Sendable>: @unchecked Sendable {
    let getValue: @MainActor () -> Value
    let setValue: @MainActor (Value) -> Void
}

@MainActor
func mainActorBinding<Value: Sendable>(
    get: @escaping @MainActor () -> Value,
    set: @escaping @MainActor (Value) -> Void
) -> Binding<Value> {
    let access = MainActorBindingAccess(getValue: get, setValue: set)
    return Binding(
        get: {
            MainActor.assumeIsolated {
                access.getValue()
            }
        },
        set: { value in
            MainActor.assumeIsolated {
                access.setValue(value)
            }
        }
    )
}
