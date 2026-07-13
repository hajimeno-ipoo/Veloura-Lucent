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
    func windowAppearanceStateKeepsSavedAmountAcrossAccessibilityChanges() {
        let normal = AppAppearanceSettings.windowAppearanceState(
            materialAmount: 0.37,
            isFullScreen: false,
            reduceTransparency: false
        )
        let reducedTransparency = AppAppearanceSettings.windowAppearanceState(
            materialAmount: normal.materialAmount,
            isFullScreen: false,
            reduceTransparency: true
        )
        let restored = AppAppearanceSettings.windowAppearanceState(
            materialAmount: reducedTransparency.materialAmount,
            isFullScreen: false,
            reduceTransparency: false
        )

        #expect(!normal.usesOpaqueBackground)
        #expect(reducedTransparency.usesOpaqueBackground)
        #expect(reducedTransparency.materialAmount == 0.37)
        #expect(restored == normal)
    }

    @Test
    func windowAppearanceStateUsesOpaqueBackgroundInFullScreen() {
        let state = AppAppearanceSettings.windowAppearanceState(
            materialAmount: 0.42,
            isFullScreen: true,
            reduceTransparency: false
        )

        #expect(state.usesOpaqueBackground)
        #expect(state.materialAmount == 0.42)
        #expect(state.updatingFullScreen(false).usesOpaqueBackground == false)
    }
}
