import AppKit
import SwiftUI

@MainActor
struct VelouraAboutView: View {
    struct AssetPresentation: Equatable, Identifiable, Sendable {
        let kind: StemModelAssetKind
        let fileName: String
        let byteCount: Int64
        let sha256: String
        let stableDownloadURL: String

        var id: StemModelAssetKind { kind }
    }

    struct ModelPresentation: Equatable, Identifiable, Sendable {
        let model: StemSeparationModel
        let repository: String
        let revision: String
        let license: String
        let licenseStatus: String
        let provenance: String
        let sourceHosts: String
        let totalByteCount: Int64
        let saveDestination: String
        let assets: [AssetPresentation]

        var id: StemSeparationModel { model }

        init(model: StemSeparationModel, manifest: StemModelManifest) {
            self.model = model
            repository = manifest.model.repo
            revision = manifest.model.revision
            license = manifest.model.licenseMetadata
            licenseStatus = model.rightsAndProvenance.licenseStatus
            provenance = model.rightsAndProvenance.provenance
            sourceHosts = Set(
                manifest.downloadableModelAssets.compactMap {
                    URL(string: $0.downloadURL)?.host
                }
            )
            .sorted()
            .joined(separator: " / ")
            totalByteCount = manifest.downloadableModelAssets.reduce(0) {
                $0 + $1.byteCount
            }
            saveDestination = NSString(
                string: StemModelStorePaths.production.rootURL.path
            ).abbreviatingWithTildeInPath
            assets = manifest.downloadableModelAssets
                .sorted {
                    Self.assetSortOrder($0.kind) < Self.assetSortOrder($1.kind)
                }
                .map {
                    AssetPresentation(
                        kind: $0.kind,
                        fileName: URL(fileURLWithPath: $0.installationRelativePath)
                            .lastPathComponent,
                        byteCount: $0.byteCount,
                        sha256: $0.sha256,
                        stableDownloadURL: $0.downloadURL
                    )
                }
        }

        private static func assetSortOrder(_ kind: StemModelAssetKind) -> Int {
            switch kind {
            case .modelWeights: 0
            case .modelConfiguration: 1
            case .metalLibrary: 2
            }
        }
    }

    @State private var selectedModel: StemSeparationModel = .htdemucs
    @State private var isWindowFullScreen = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let presentations: [StemSeparationModel: ModelPresentation]
    private let loadingErrors: [StemSeparationModel: String]

    init() {
        var presentations: [StemSeparationModel: ModelPresentation] = [:]
        var loadingErrors: [StemSeparationModel: String] = [:]
        for model in StemSeparationModel.allCases {
            do {
                let validator = StemModelAssetValidator(selectedModel: model)
                let manifest = try validator.loadBundledManifest()
                _ = try validator.validateManifest(manifest)
                presentations[model] = ModelPresentation(
                    model: model,
                    manifest: manifest
                )
            } catch {
                loadingErrors[model] = error.localizedDescription
            }
        }
        self.presentations = presentations
        self.loadingErrors = loadingErrors
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                appHeader
                Divider()
                modelPicker
                Divider()
                selectedModelInformation
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .frame(minWidth: 680, idealWidth: 760, minHeight: 560, idealHeight: 720)
        .containerBackground(.regularMaterial, for: .window)
        .background(
            WindowChromeConfigurator(
                minSize: NSSize(width: 680, height: 560),
                appearanceState: AppAppearanceSettings.windowAppearanceState(
                    materialAmount: 0,
                    isBlurEnabled: true,
                    blurLevel: .thin,
                    isFullScreen: isWindowFullScreen,
                    reduceTransparency: reduceTransparency
                ),
                hidesTitle: false,
                extendsContentIntoTitlebar: true,
                isFullScreen: $isWindowFullScreen
            )
        )
        .windowMinimizeBehavior(.disabled)
        .accessibilityElement(children: .contain)
    }

    private var appHeader: some View {
        HStack(spacing: 16) {
            Image(nsImage: applicationIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Veloura Lucent")
                    .font(.largeTitle.bold())
                Text("音声を補正し、マスタリングで最終版に仕上げます。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let applicationVersion {
                    Text(applicationVersion)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var modelPicker: some View {
        LiquidGlassSegmentedPicker(
            title: "AIモデル",
            options: StemSeparationModel.allCases,
            selection: $selectedModel,
            label: \.displayName
        )
        .accessibilityHint("表示するAIモデルの配布情報を切り替えます。")
    }

    @ViewBuilder
    private var selectedModelInformation: some View {
        if let presentation = presentations[selectedModel] {
            VStack(alignment: .leading, spacing: 16) {
                modelContract(presentation)
                ForEach(presentation.assets) { asset in
                    Divider()
                    assetInformation(asset)
                }
            }
        } else {
            Label(
                loadingErrors[selectedModel] ?? "AIモデル情報を読み込めません。",
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.red)
            .textSelection(.enabled)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func modelContract(_ presentation: ModelPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(presentation.model.displayName)
                .font(.title2.bold())
            informationList([
                (label: "取得元", value: presentation.repository),
                (label: "固定Revision", value: presentation.revision),
                (label: "License", value: presentation.license),
                (label: "ライセンス情報", value: presentation.licenseStatus),
                (label: "モデルの来歴", value: presentation.provenance),
                (label: "通信先ホスト", value: presentation.sourceHosts),
                (label: "合計容量", value: "\(presentation.totalByteCount) bytes"),
                (label: "保存先", value: presentation.saveDestination),
            ])
        }
    }

    private func assetInformation(_ asset: AssetPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(asset.fileName, systemImage: "doc")
                .font(.title3.bold())
            informationList([
                (label: "容量", value: "\(asset.byteCount) bytes"),
                (label: "SHA-256", value: asset.sha256),
                (label: "固定配布URL", value: asset.stableDownloadURL),
            ])
        }
    }

    private func informationList(_ rows: [(label: String, value: String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                detailValue(label: row.label, value: row.value)
                    .padding(.vertical, 10)

                if index < rows.count - 1 {
                    Divider()
                }
            }
        }
    }

    private func detailValue(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var applicationIcon: NSImage {
        if let iconURL = AppResourceBundle.url(
            forResource: "AppIcon-1024",
            withExtension: "png"
        ),
           let image = NSImage(contentsOf: iconURL) {
            return image
        }
        return NSApp.applicationIconImage
    }

    private var applicationVersion: String? {
        guard let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String else {
            return nil
        }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String else {
            return "バージョン \(trimmed)"
        }
        let trimmedBuild = build.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBuild.isEmpty else {
            return "バージョン \(trimmed)"
        }
        return "バージョン \(trimmed)（ビルド \(trimmedBuild)）"
    }
}
