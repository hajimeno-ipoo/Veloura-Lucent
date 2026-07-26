import Foundation

struct StemModelStorePaths: Equatable, Sendable {
    static let applicationSupportDirectoryName = "Veloura Lucent"
    static let receiptFileName = "installation-receipt.json"
    static let activePointerFileName = "active.json"

    let rootURL: URL

    static var production: StemModelStorePaths {
        StemModelStorePaths(
            rootURL: URL.applicationSupportDirectory
                .appending(path: applicationSupportDirectoryName, directoryHint: .isDirectory)
                .appending(path: "StemModels", directoryHint: .isDirectory)
        )
    }

    var stagingRootURL: URL {
        rootURL.appending(path: "Staging", directoryHint: .isDirectory)
    }

    var versionsRootURL: URL {
        rootURL.appending(path: "Versions", directoryHint: .isDirectory)
    }

    var activePointerURL: URL {
        rootURL.appending(path: Self.activePointerFileName, directoryHint: .notDirectory)
    }

    func stagingDirectoryURL(operationIdentifier: UUID) -> URL {
        stagingRootURL.appending(
            path: operationIdentifier.uuidString.lowercased(),
            directoryHint: .isDirectory
        )
    }

    func assetSetDirectoryURL(assetSetIdentifier: String) -> URL {
        versionsRootURL.appending(path: assetSetIdentifier, directoryHint: .isDirectory)
    }

    func generationDirectoryURL(assetSetIdentifier: String, generationIdentifier: UUID) -> URL {
        assetSetDirectoryURL(assetSetIdentifier: assetSetIdentifier)
            .appending(path: generationIdentifier.uuidString.lowercased(), directoryHint: .isDirectory)
    }

    func receiptURL(in generationDirectoryURL: URL) -> URL {
        generationDirectoryURL.appending(path: Self.receiptFileName, directoryHint: .notDirectory)
    }
}
