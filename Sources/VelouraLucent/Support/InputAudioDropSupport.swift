import Foundation
import UniformTypeIdentifiers

enum InputAudioDropSupport {
    enum Validation: Equatable {
        case accepted(URL)
        case rejected
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
