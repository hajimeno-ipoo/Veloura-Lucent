import Observation

@Observable
final class ProcessingSettingsState {
    var selectedMasteringProfile: MasteringProfile = .streaming
    var editableMasteringSettings: MasteringSettings = MasteringProfile.streaming.settings
    var isUsingCustomMasteringSettings = false
    var showAdvancedMasteringSettings = false
    var selectedDenoiseStrength: DenoiseStrength = .balanced
    var editableCorrectionSettings: CorrectionSettings = DenoiseStrength.balanced.settings
    var isUsingCustomCorrectionSettings = false
    var showAdvancedCorrectionSettings = false
    var appliedCorrectionSettings: CorrectionSettings?
    var appliedMasteringSettings: MasteringSettings?
    var selectedAnalysisMode: AudioAnalysisMode = .auto

    func applyMasteringProfile(_ profile: MasteringProfile) {
        selectedMasteringProfile = profile
        editableMasteringSettings = profile.settings
        isUsingCustomMasteringSettings = false
    }

    func resetMasteringSettingsToProfile() {
        applyMasteringProfile(selectedMasteringProfile)
    }

    func updateMasteringSettings(_ update: (inout MasteringSettings) -> Void) {
        update(&editableMasteringSettings)
        isUsingCustomMasteringSettings = true
    }

    func applyCorrectionProfile(_ profile: DenoiseStrength) {
        selectedDenoiseStrength = profile
        editableCorrectionSettings = profile.settings
        isUsingCustomCorrectionSettings = false
    }

    func resetCorrectionSettingsToProfile() {
        applyCorrectionProfile(selectedDenoiseStrength)
    }

    func updateCorrectionSettings(_ update: (inout CorrectionSettings) -> Void) {
        update(&editableCorrectionSettings)
        editableCorrectionSettings.profile = selectedDenoiseStrength
        isUsingCustomCorrectionSettings = true
    }

    func resetAppliedSettings() {
        appliedCorrectionSettings = nil
        appliedMasteringSettings = nil
    }

    func resetAppliedMasteringSettings() {
        appliedMasteringSettings = nil
    }

    func storeAppliedCorrectionSettings(_ settings: CorrectionSettings?) {
        appliedCorrectionSettings = settings ?? appliedCorrectionSettings ?? editableCorrectionSettings
    }

    func storeAppliedMasteringSettings(_ settings: MasteringSettings?) {
        appliedMasteringSettings = settings ?? appliedMasteringSettings ?? editableMasteringSettings
    }
}
