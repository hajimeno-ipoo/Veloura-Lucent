import Foundation

enum AppAppearanceSettings {
    static let windowBackgroundMaterialAmountKey = "windowBackgroundMaterialAmount"
    static let defaultWindowBackgroundMaterialAmount = 0.0
    static let windowBackgroundMaterialRange = 0.0 ... 1.0

    static func clampedWindowBackgroundMaterialAmount(_ amount: Double) -> Double {
        min(max(amount, windowBackgroundMaterialRange.lowerBound), windowBackgroundMaterialRange.upperBound)
    }

    static func windowBackgroundMaterialPercent(_ amount: Double) -> Int {
        Int((clampedWindowBackgroundMaterialAmount(amount) * 100).rounded())
    }

    static func storedWindowBackgroundMaterialAmount(defaults: UserDefaults = .standard) -> Double {
        clampedWindowBackgroundMaterialAmount(defaults.double(forKey: windowBackgroundMaterialAmountKey))
    }

    static func saveWindowBackgroundMaterialAmount(
        _ amount: Double,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(clampedWindowBackgroundMaterialAmount(amount), forKey: windowBackgroundMaterialAmountKey)
    }
}
