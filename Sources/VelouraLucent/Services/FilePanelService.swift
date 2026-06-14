import AppKit
import UniformTypeIdentifiers

@MainActor
enum FilePanelService {
    static func chooseAudioFile(completion: @escaping @MainActor (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .audio,
            UTType(filenameExtension: "wav"),
            UTType(filenameExtension: "mp3"),
            UTType(filenameExtension: "m4a"),
            UTType(filenameExtension: "flac"),
            UTType(filenameExtension: "aiff")
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "開く"
        panel.begin { response in
            Task { @MainActor in
                completion(response == .OK ? panel.url : nil)
            }
        }
    }

    static func chooseSaveLocation(
        suggestedFileName: String,
        allowedContentTypes: [UTType],
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = allowedContentTypes
        panel.nameFieldStringValue = suggestedFileName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.prompt = "書き出し"
        panel.begin { response in
            Task { @MainActor in
                completion(response == .OK ? panel.url : nil)
            }
        }
    }
}
