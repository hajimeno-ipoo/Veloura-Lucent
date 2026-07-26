import Foundation

enum WindowBackgroundBlurLevel: String, CaseIterable, Sendable {
    case ultraThin
    case thin
    case regular
    case thick
    case ultraThick

    var title: String {
        switch self {
        case .ultraThin: "最も弱い"
        case .thin: "弱い"
        case .regular: "標準"
        case .thick: "強い"
        case .ultraThick: "最も強い"
        }
    }

    var sliderPosition: Double {
        Double(Self.allCases.firstIndex(of: self) ?? 0)
    }

    static var sliderRange: ClosedRange<Double> {
        0 ... Double(allCases.count - 1)
    }

    static func level(for sliderPosition: Double) -> WindowBackgroundBlurLevel {
        let index = Int(sliderPosition.rounded())
        let clampedIndex = min(max(index, 0), allCases.count - 1)
        return allCases[clampedIndex]
    }
}

struct WindowAppearanceState: Equatable {
    let materialAmount: Double
    let isBlurEnabled: Bool
    let blurLevel: WindowBackgroundBlurLevel
    let isFullScreen: Bool
    let reduceTransparency: Bool

    var effectiveBlurLevel: WindowBackgroundBlurLevel {
        isBlurEnabled ? blurLevel : .thin
    }

    var usesOpaqueBackground: Bool {
        isFullScreen || reduceTransparency
    }

    func updatingFullScreen(_ isFullScreen: Bool) -> WindowAppearanceState {
        WindowAppearanceState(
            materialAmount: materialAmount,
            isBlurEnabled: isBlurEnabled,
            blurLevel: blurLevel,
            isFullScreen: isFullScreen,
            reduceTransparency: reduceTransparency
        )
    }
}

enum AppAppearanceSettings {
    static let windowBackgroundMaterialAmountKey = "windowBackgroundMaterialAmount"
    static let windowBackgroundBlurEnabledKey = "windowBackgroundBlurEnabled"
    static let windowBackgroundBlurLevelKey = "windowBackgroundBlurLevel"
    static let defaultWindowBackgroundMaterialAmount = 0.0
    static let defaultWindowBackgroundBlurEnabled = true
    static let defaultWindowBackgroundBlurLevel = WindowBackgroundBlurLevel.thin
    static let windowBackgroundMaterialRange = 0.0 ... 1.0

    static func clampedWindowBackgroundMaterialAmount(_ amount: Double) -> Double {
        min(max(amount, windowBackgroundMaterialRange.lowerBound), windowBackgroundMaterialRange.upperBound)
    }

    static func windowBackgroundMaterialPercent(_ amount: Double) -> Int {
        Int((clampedWindowBackgroundMaterialAmount(amount) * 100).rounded())
    }

    static func windowAppearanceState(
        materialAmount: Double,
        isBlurEnabled: Bool,
        blurLevel: WindowBackgroundBlurLevel,
        isFullScreen: Bool,
        reduceTransparency: Bool
    ) -> WindowAppearanceState {
        WindowAppearanceState(
            materialAmount: clampedWindowBackgroundMaterialAmount(materialAmount),
            isBlurEnabled: isBlurEnabled,
            blurLevel: blurLevel,
            isFullScreen: isFullScreen,
            reduceTransparency: reduceTransparency
        )
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

    static func storedWindowBackgroundBlurEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: windowBackgroundBlurEnabledKey) != nil else {
            return defaultWindowBackgroundBlurEnabled
        }
        return defaults.bool(forKey: windowBackgroundBlurEnabledKey)
    }

    static func saveWindowBackgroundBlurEnabled(
        _ isEnabled: Bool,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: windowBackgroundBlurEnabledKey)
    }

    static func storedWindowBackgroundBlurLevel(
        defaults: UserDefaults = .standard
    ) -> WindowBackgroundBlurLevel {
        guard
            let rawValue = defaults.string(forKey: windowBackgroundBlurLevelKey),
            let level = WindowBackgroundBlurLevel(rawValue: rawValue)
        else {
            return defaultWindowBackgroundBlurLevel
        }
        return level
    }

    static func saveWindowBackgroundBlurLevel(
        _ level: WindowBackgroundBlurLevel,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(level.rawValue, forKey: windowBackgroundBlurLevelKey)
    }
}
