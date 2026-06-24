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
}
