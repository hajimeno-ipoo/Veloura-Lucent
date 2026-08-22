import Foundation
import Testing
@testable import VelouraLucent

struct AppResourceBundleTests {
    @Test
    func developmentRunUsesSwiftPackageResources() {
        #expect(AppResourceBundle.bundle != nil)
        #expect(AppResourceBundle.url(forResource: "2", withExtension: "png") != nil)
        #expect(AppResourceBundle.resourceURL?.lastPathComponent == AppResourceBundle.bundleName)
    }

    @Test
    func packagedAppUsesFormalContentsResourcesBundle() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let appURL = root.appending(path: "Veloura Lucent.app", directoryHint: .isDirectory)
        let resourcesURL = appURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        let resourceBundleURL = resourcesURL
            .appending(path: AppResourceBundle.bundleName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: resourceBundleURL, withIntermediateDirectories: true)
        try Data(minimalBundleInfoPlist.utf8).write(
            to: resourceBundleURL.appending(path: "Info.plist")
        )
        try Data("formal-resource".utf8).write(
            to: resourceBundleURL.appending(path: "marker.txt")
        )

        let resolved = AppResourceBundle.resolve(
            mainBundleURL: appURL,
            mainResourceURL: resourcesURL,
            developmentBundle: .main
        )

        #expect(resolved?.bundleURL.standardizedFileURL == resourceBundleURL.standardizedFileURL)
        #expect(resolved?.url(forResource: "marker", withExtension: "txt") != nil)
    }

    @Test
    func packagedAppDoesNotFallBackToDeveloperBuildDirectory() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let appURL = root.appending(path: "Veloura Lucent.app", directoryHint: .isDirectory)
        let resourcesURL = appURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let resolved = AppResourceBundle.resolve(
            mainBundleURL: appURL,
            mainResourceURL: resourcesURL,
            developmentBundle: .main
        )

        #expect(resolved == nil)
    }

    @Test
    func bundledManifestLoadsThroughDevelopmentResolver() throws {
        let manifest = try StemModelAssetValidator().loadBundledManifest()

        #expect(manifest.schemaVersion == 2)
        #expect(manifest.model.revision == "d4519e24ddc2dd4a11d56a193092433d852c3961")
    }

    private var minimalBundleInfoPlist: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleIdentifier</key>
          <string>com.codex.VelouraLucent.Resources</string>
          <key>CFBundlePackageType</key>
          <string>BNDL</string>
        </dict>
        </plist>
        """
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "VelouraAppResourceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
