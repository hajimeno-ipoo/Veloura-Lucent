import AppKit
import UniformTypeIdentifiers

enum InputAudioDropSupport {
    enum Validation: Equatable {
        case accepted(URL)
        case rejected
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? []
        return objects.compactMap { object in
            if let url = object as? URL {
                return url
            }
            if let url = object as? NSURL {
                return url as URL
            }
            return nil
        }
    }

    static func isAcceptedAudioFile(_ url: URL, fileManager: FileManager = .default) -> Bool {
        guard url.isFileURL else { return false }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }

        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .audio)
    }

    static func validate(_ urls: [URL], fileManager: FileManager = .default) -> Validation {
        guard urls.count == 1, let url = urls.first, isAcceptedAudioFile(url, fileManager: fileManager) else {
            return .rejected
        }
        return .accepted(url)
    }
}
