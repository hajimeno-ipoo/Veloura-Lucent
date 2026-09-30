import SwiftUI

/// Resolves presentation strings when the app's language environment changes.
/// A value that has no catalog entry is displayed as received.
struct AppLocalizedText: View {
    let key: String
    @Environment(\.locale) private var locale

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(AppLanguageSettings.string(key))
            .environment(\.locale, locale)
    }
}
