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

    static func chooseImageFile(
        attachedTo parentWindow: NSWindow? = nil,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .image,
            UTType(filenameExtension: "png"),
            UTType(filenameExtension: "jpg"),
            UTType(filenameExtension: "jpeg"),
            UTType(filenameExtension: "heic"),
            UTType(filenameExtension: "tiff"),
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "選ぶ"
        present(panel, attachedTo: parentWindow, completion: completion)
    }

    static func chooseSaveLocation(
        suggestedFileName: String,
        allowedContentTypes: [UTType],
        attachedTo parentWindow: NSWindow? = nil,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = allowedContentTypes
        panel.nameFieldStringValue = suggestedFileName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.prompt = "書き出し"
        present(panel, attachedTo: parentWindow, completion: completion)
    }

    private static func present(
        _ panel: NSSavePanel,
        attachedTo parentWindow: NSWindow?,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            Task { @MainActor in
                completion(response == .OK ? panel.url : nil)
            }
        }

        if let parentWindow {
            panel.beginSheetModal(for: parentWindow, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }
}
