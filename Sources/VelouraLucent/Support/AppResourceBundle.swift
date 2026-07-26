import Foundation

enum AppResourceBundle {
    static let bundleName = "VelouraLucent_VelouraLucent.bundle"

    static var bundle: Bundle? {
        if Bundle.main.bundleURL.pathExtension == "app" {
            return resolve(
                mainBundleURL: Bundle.main.bundleURL,
                mainResourceURL: Bundle.main.resourceURL,
                developmentBundle: .main
            )
        }
        return .module
    }

    static var resourceURL: URL? {
        bundle?.resourceURL
    }

    static func url(
        forResource name: String,
        withExtension extensionName: String?,
        subdirectory: String? = nil
    ) -> URL? {
        bundle?.url(
            forResource: name,
            withExtension: extensionName,
            subdirectory: subdirectory
        )
    }

    static func resolve(
        mainBundleURL: URL,
        mainResourceURL: URL?,
        developmentBundle: Bundle
    ) -> Bundle? {
        guard mainBundleURL.pathExtension == "app" else {
            return developmentBundle
        }
        guard let mainResourceURL else { return nil }

        let packagedBundleURL = mainResourceURL
            .appending(path: bundleName, directoryHint: .isDirectory)
        return Bundle(url: packagedBundleURL)
    }
}
