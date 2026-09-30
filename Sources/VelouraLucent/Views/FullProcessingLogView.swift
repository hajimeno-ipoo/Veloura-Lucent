import SwiftUI
import UniformTypeIdentifiers

struct ProcessingLogJSONExport: Encodable {
    struct Section: Encodable {
        let id: String
        let title: String
        let lines: [String]
    }

    let mode: String
    let exportedAt: Date
    let sections: [Section]

    static func data(mode: String, sections: [ProcessingLogSection], exportedAt: Date = .now) throws -> Data {
        let export = ProcessingLogJSONExport(
            mode: mode,
            exportedAt: exportedAt,
            sections: sections.map {
                Section(
                    id: $0.id,
                    title: AppLanguageSettings.string($0.title),
                    lines: $0.lines.map(ProcessingLogLineLocalization.string)
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }
}

struct FullProcessingLogLayout: View {
    let sections: [ProcessingLogSection]
    let mode: ProcessingMode
    let inputURL: URL?
    let onDismiss: () -> Void
    @State private var exportErrorMessage = ""
    @State private var isExportErrorPresented = false

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("処理ログ")
                        .font(.title2.bold())
                    Spacer()
                    Button("JSONを書き出す", systemImage: "square.and.arrow.up") {
                        exportJSON()
                    }
                    .disabled(inputURL == nil || sections.allSatisfy(\.lines.isEmpty))
                    .help("表示中の処理ログ全文をJSONファイルに保存します")
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                            .velouraAdaptiveGlass(in: Circle(), interactive: true)
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .accessibilityLabel("閉じる")
                    .help("詳細ログを閉じます")
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                ScrollView {
                    ProcessingLogView(sections: sections)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        .velouraTransientOverlayScrollIndicators()
                }
                .scrollContentBackground(.hidden)
            }
            .velouraAdaptiveGlass(in: .rect(cornerRadius: 18))
        }
        .frame(minWidth: 640, idealWidth: 840, minHeight: 520, idealHeight: 680)
        .padding(18)
        .alert("処理ログを書き出せませんでした", isPresented: $isExportErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
    }

    private func exportJSON() {
        guard let inputURL else { return }
        do {
            let data = try ProcessingLogJSONExport.data(mode: mode.rawValue, sections: sections)
            FilePanelService.chooseSaveLocation(
                suggestedFileName: ExportFileName.processingLog(inputURL: inputURL, mode: mode),
                allowedContentTypes: [.json]
            ) { destinationURL in
                guard let destinationURL else { return }
                do {
                    try data.write(to: destinationURL, options: .atomic)
                } catch {
                    showExportError(error)
                }
            }
        } catch {
            showExportError(error)
        }
    }

    private func showExportError(_ error: Error) {
        exportErrorMessage = error.localizedDescription
        isExportErrorPresented = true
    }
}

struct FullProcessingLogView: View {
    @Bindable var job: ProcessingJob
    let onDismiss: () -> Void

    var body: some View {
        FullProcessingLogLayout(
            sections: [
                ProcessingLogSection(
                    id: "correction",
                    title: "補正ログ",
                    lines: job.logLines,
                    placeholder: "ここに補正ログが表示されます。"
                ),
                ProcessingLogSection(
                    id: "mastering",
                    title: "マスタリングログ",
                    lines: job.masteringLogLines,
                    placeholder: "ここにマスタリングログが表示されます。"
                ),
            ],
            mode: .standard,
            inputURL: job.inputFile,
            onDismiss: onDismiss
        )
    }
}
