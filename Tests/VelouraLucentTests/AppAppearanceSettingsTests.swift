import Foundation
import Testing
@testable import VelouraLucent

struct AppAppearanceSettingsTests {
    @Test
    func windowBackgroundMaterialAmountIsClampedToSupportedRange() {
        #expect(AppAppearanceSettings.clampedWindowBackgroundMaterialAmount(-0.4) == 0)
        #expect(AppAppearanceSettings.clampedWindowBackgroundMaterialAmount(0.42) == 0.42)
        #expect(AppAppearanceSettings.clampedWindowBackgroundMaterialAmount(1.4) == 1)
    }

    @Test
    func windowBackgroundMaterialPercentUsesClampedAmount() {
        #expect(AppAppearanceSettings.windowBackgroundMaterialPercent(0) == 0)
        #expect(AppAppearanceSettings.windowBackgroundMaterialPercent(0.425) == 43)
        #expect(AppAppearanceSettings.windowBackgroundMaterialPercent(1.4) == 100)
    }

    @Test
    func windowBackgroundMaterialAmountPersistsWithStableUserDefaultsKey() {
        let suiteName = "VelouraLucent.AppAppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        AppAppearanceSettings.saveWindowBackgroundMaterialAmount(0.37, defaults: defaults)

        #expect(defaults.double(forKey: AppAppearanceSettings.windowBackgroundMaterialAmountKey) == 0.37)
        #expect(AppAppearanceSettings.storedWindowBackgroundMaterialAmount(defaults: defaults) == 0.37)
    }

    @Test
    func windowBackgroundMaterialAmountPersistenceClampsUnsupportedValues() {
        let suiteName = "VelouraLucent.AppAppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        AppAppearanceSettings.saveWindowBackgroundMaterialAmount(1.4, defaults: defaults)

        #expect(defaults.double(forKey: AppAppearanceSettings.windowBackgroundMaterialAmountKey) == 1)
        #expect(AppAppearanceSettings.storedWindowBackgroundMaterialAmount(defaults: defaults) == 1)
    }

    @Test
    func windowBackgroundBlurLevelUsesFiveClampedSliderPositions() {
        #expect(WindowBackgroundBlurLevel.allCases.count == 5)
        #expect(WindowBackgroundBlurLevel.level(for: -1) == .ultraThin)
        #expect(WindowBackgroundBlurLevel.level(for: 0) == .ultraThin)
        #expect(WindowBackgroundBlurLevel.level(for: 1) == .thin)
        #expect(WindowBackgroundBlurLevel.level(for: 2) == .regular)
        #expect(WindowBackgroundBlurLevel.level(for: 3) == .thick)
        #expect(WindowBackgroundBlurLevel.level(for: 4) == .ultraThick)
        #expect(WindowBackgroundBlurLevel.level(for: 5) == .ultraThick)
    }

    @Test
    func windowBackgroundBlurDefaultsPreserveCurrentThinMaterial() {
        let suiteName = "VelouraLucent.AppAppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        #expect(AppAppearanceSettings.storedWindowBackgroundBlurEnabled(defaults: defaults))
        #expect(AppAppearanceSettings.storedWindowBackgroundBlurLevel(defaults: defaults) == .thin)
    }

    @Test
    func windowBackgroundBlurSettingsPersist() {
        let suiteName = "VelouraLucent.AppAppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        AppAppearanceSettings.saveWindowBackgroundBlurEnabled(false, defaults: defaults)
        AppAppearanceSettings.saveWindowBackgroundBlurLevel(.ultraThick, defaults: defaults)

        #expect(!AppAppearanceSettings.storedWindowBackgroundBlurEnabled(defaults: defaults))
        #expect(AppAppearanceSettings.storedWindowBackgroundBlurLevel(defaults: defaults) == .ultraThick)
    }

    @Test
    func invalidWindowBackgroundBlurLevelFallsBackToCurrentThinMaterial() {
        let suiteName = "VelouraLucent.AppAppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set("unsupported", forKey: AppAppearanceSettings.windowBackgroundBlurLevelKey)

        #expect(AppAppearanceSettings.storedWindowBackgroundBlurLevel(defaults: defaults) == .thin)
    }

    @Test
    func windowAppearanceStateKeepsSavedAmountAcrossAccessibilityChanges() {
        let normal = AppAppearanceSettings.windowAppearanceState(
            materialAmount: 0.37,
            isBlurEnabled: false,
            blurLevel: .thick,
            isFullScreen: false,
            reduceTransparency: false
        )
        let reducedTransparency = AppAppearanceSettings.windowAppearanceState(
            materialAmount: normal.materialAmount,
            isBlurEnabled: normal.isBlurEnabled,
            blurLevel: normal.blurLevel,
            isFullScreen: false,
            reduceTransparency: true
        )
        let restored = AppAppearanceSettings.windowAppearanceState(
            materialAmount: reducedTransparency.materialAmount,
            isBlurEnabled: reducedTransparency.isBlurEnabled,
            blurLevel: reducedTransparency.blurLevel,
            isFullScreen: false,
            reduceTransparency: false
        )

        #expect(!normal.usesOpaqueBackground)
        #expect(reducedTransparency.usesOpaqueBackground)
        #expect(reducedTransparency.materialAmount == 0.37)
        #expect(reducedTransparency.isBlurEnabled == false)
        #expect(reducedTransparency.blurLevel == .thick)
        #expect(reducedTransparency.effectiveBlurLevel == .thin)
        #expect(restored == normal)
    }

    @Test
    func windowAppearanceStateUsesOpaqueBackgroundInFullScreen() {
        let state = AppAppearanceSettings.windowAppearanceState(
            materialAmount: 0.42,
            isBlurEnabled: true,
            blurLevel: .regular,
            isFullScreen: true,
            reduceTransparency: false
        )

        #expect(state.usesOpaqueBackground)
        #expect(state.materialAmount == 0.42)
        #expect(state.isBlurEnabled)
        #expect(state.blurLevel == .regular)
        #expect(state.effectiveBlurLevel == .regular)
        #expect(state.updatingFullScreen(false).usesOpaqueBackground == false)
    }
}
