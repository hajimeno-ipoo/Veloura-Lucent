import CoreGraphics
import Foundation
import Observation
import UniformTypeIdentifiers

struct ComparisonVideoSource: Identifiable, Hashable, Sendable {
    let id: String
    let fileURL: URL
    let trackTitle: String
    let roleTitle: String
    private let fingerprint: ComparisonVideoSourceFingerprint?

    init(fileURL: URL, trackTitle: String, roleTitle: String) {
        let normalizedURL = fileURL.standardizedFileURL
        id = normalizedURL.path(percentEncoded: false)
        self.fileURL = normalizedURL
        self.trackTitle = trackTitle
        self.roleTitle = roleTitle
        fingerprint = ComparisonVideoSourceFingerprint.read(from: normalizedURL)
    }

    var matchesCurrentFile: Bool {
        guard let fingerprint else { return false }
        return fingerprint == ComparisonVideoSourceFingerprint.read(from: fileURL)
    }
}

private struct ComparisonVideoSourceFingerprint: Hashable, Sendable {
    let fileSize: UInt64
    let modificationTime: TimeInterval
    let systemFileNumber: UInt64

    static func read(from url: URL) -> ComparisonVideoSourceFingerprint? {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false)
        ), let size = attributes[.size] as? NSNumber,
        let modificationDate = attributes[.modificationDate] as? Date,
        let fileNumber = attributes[.systemFileNumber] as? NSNumber else {
            return nil
        }
        return ComparisonVideoSourceFingerprint(
            fileSize: size.uint64Value,
            modificationTime: modificationDate.timeIntervalSinceReferenceDate,
            systemFileNumber: fileNumber.uint64Value
        )
    }
}

struct ComparisonVideoLaunch: Sendable {
    let mode: ProcessingMode
    let sources: [ComparisonVideoSource]
}

enum ComparisonVideoOrientation: String, CaseIterable, Identifiable, Sendable {
    case landscape
    case portrait

    var id: String { rawValue }

    var title: String {
        switch self {
        case .landscape: "横型"
        case .portrait: "縦型"
        }
    }

    var pixelSize: CGSize {
        switch self {
        case .landscape: CGSize(width: 1_920, height: 1_080)
        case .portrait: CGSize(width: 1_080, height: 1_920)
        }
    }
}

enum ComparisonVideoFormat: String, CaseIterable, Identifiable, Sendable {
    case mp4
    case mov

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }

    var contentType: UTType {
        switch self {
        case .mp4: .mpeg4Movie
        case .mov: .quickTimeMovie
        }
    }
}

struct ComparisonVideoSegment: Equatable, Sendable {
    let sourceIndex: Int
    let sourceStartTime: TimeInterval
    let duration: TimeInterval
}

struct ComparisonVideoPlan: Equatable, Sendable {
    static let maximumOutputDuration: TimeInterval = 60
    static let segmentDuration: TimeInterval = 15

    let sourceStartTime: TimeInterval
    let sourceDuration: TimeInterval
    let segments: [ComparisonVideoSegment]

    var outputDuration: TimeInterval {
        sourceDuration
    }

    static func make(
        sourceDuration: TimeInterval,
        requestedStartTime: TimeInterval
    ) -> ComparisonVideoPlan? {
        guard sourceDuration.isFinite, sourceDuration > 0 else { return nil }
        let usableDuration = min(maximumOutputDuration, sourceDuration)
        let maximumStart = max(sourceDuration - usableDuration, 0)
        let start = min(max(requestedStartTime, 0), maximumStart)
        var segments: [ComparisonVideoSegment] = []
        var elapsed: TimeInterval = 0
        var sourceIndex = 0
        while elapsed < usableDuration {
            let duration = min(segmentDuration, usableDuration - elapsed)
            segments.append(ComparisonVideoSegment(
                sourceIndex: sourceIndex,
                sourceStartTime: start + elapsed,
                duration: duration
            ))
            elapsed += duration
            sourceIndex = sourceIndex == 0 ? 1 : 0
        }
        return ComparisonVideoPlan(
            sourceStartTime: start,
            sourceDuration: usableDuration,
            segments: segments
        )
    }

    func segment(at outputTime: TimeInterval) -> (index: Int, segment: ComparisonVideoSegment, localTime: TimeInterval) {
        var elapsed: TimeInterval = 0
        for (index, segment) in segments.enumerated() {
            let end = elapsed + segment.duration
            if outputTime < end || index == segments.indices.last {
                return (index, segment, max(outputTime - elapsed, 0))
            }
            elapsed = end
        }
        let lastIndex = segments.indices.last ?? 0
        let last = segments[lastIndex]
        return (lastIndex, last, last.duration)
    }
}

struct ComparisonVideoFrameState: Sendable {
    let trackTitle: String
    let firstRoleTitle: String
    let secondRoleTitle: String
    let plan: ComparisonVideoPlan
    let outputTime: TimeInterval

    var activeSourceIndex: Int {
        plan.segment(at: outputTime).segment.sourceIndex
    }

    var activeRoleTitle: String {
        activeSourceIndex == 0 ? firstRoleTitle : secondRoleTitle
    }

    var transitionProgress: Double {
        let location = plan.segment(at: outputTime)
        let transitionDuration = min(0.3, location.segment.duration)
        guard transitionDuration > 0 else { return 1 }
        return min(max(location.localTime / transitionDuration, 0), 1)
    }
}

@MainActor
@Observable
final class ComparisonVideoLaunchStore {
    static let shared = ComparisonVideoLaunchStore()

    private(set) var launch: ComparisonVideoLaunch?
    private(set) var revision = UUID()

    func prepare(_ launch: ComparisonVideoLaunch) {
        self.launch = launch
        revision = UUID()
    }
}

enum ComparisonVideoSourceCatalog {
    @MainActor
    static func standard(job: ProcessingJob) -> [ComparisonVideoSource] {
        let title = trackTitle(from: job.inputFile)
        return [
            source(
                url: job.inputFile,
                title: title,
                role: "入力",
                requiresPreviewOwnership: false
            ),
            source(
                url: job.hasExistingOutput ? job.outputFile : nil,
                title: title,
                role: "補正後",
                requiresPreviewOwnership: true
            ),
            source(
                url: job.hasExistingMasteredOutput ? job.masteredOutputFile : nil,
                title: title,
                role: "最終版",
                requiresPreviewOwnership: true
            ),
        ].compactMap { $0 }
    }

    @MainActor
    static func stem(model: StemModeWorkspaceModel) -> [ComparisonVideoSource] {
        stem(
            selectedInputURL: model.selectedInputURL,
            artifactStates: model.session.artifactStates
        )
    }

    static func stem(
        selectedInputURL: URL?,
        artifactStates: [StemWorkflowArtifactDisplayState]
    ) -> [ComparisonVideoSource] {
        let title = trackTitle(from: selectedInputURL)
        let input = source(
            url: selectedInputURL,
            title: title,
            role: "入力",
            requiresPreviewOwnership: false
        )
        let artifacts: [ComparisonVideoSource] = artifactStates.compactMap { state in
            guard state.status == .valid,
                  let artifact = state.artifact,
                  artifact.kind == state.kind,
                  artifact.kind != .input44100,
                  FileManager.default.fileExists(
                    atPath: artifact.fileURL.path(percentEncoded: false)
                  ) else {
                return nil
            }
            return ComparisonVideoSource(
                fileURL: artifact.fileURL,
                trackTitle: title,
                roleTitle: artifact.kind.stemModeDisplayTitle
            )
        }
        .uniqued(by: \.id)
        .sorted { lhs, rhs in
            if lhs.roleTitle == rhs.roleTitle { return lhs.id < rhs.id }
            return lhs.roleTitle.localizedStandardCompare(rhs.roleTitle) == .orderedAscending
        }
        return ([input].compactMap { $0 } + artifacts).uniqued(by: \.id)
    }

    static func suggestedFileName(
        first: ComparisonVideoSource,
        second: ComparisonVideoSource,
        format: ComparisonVideoFormat
    ) -> String {
        let title = sanitizedFileNameComponent(first.trackTitle)
        let firstRole = sanitizedFileNameComponent(first.roleTitle)
        let secondRole = sanitizedFileNameComponent(second.roleTitle)
        return "\(title)_\(firstRole)-\(secondRole).\(format.fileExtension)"
    }

    private static func source(
        url: URL?,
        title: String,
        role: String,
        requiresPreviewOwnership: Bool
    ) -> ComparisonVideoSource? {
        guard let url else { return nil }
        let normalized = url.standardizedFileURL
        if requiresPreviewOwnership,
           normalized.deletingLastPathComponent() != PreviewFileStore.directory.standardizedFileURL {
            return nil
        }
        guard FileManager.default.fileExists(atPath: normalized.path(percentEncoded: false)) else {
            return nil
        }
        return ComparisonVideoSource(fileURL: normalized, trackTitle: title, roleTitle: role)
    }

    private static func trackTitle(from inputURL: URL?) -> String {
        inputURL?.deletingPathExtension().lastPathComponent ?? "曲名不明"
    }

    private static func sanitizedFileNameComponent(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:")
        let components = value.components(separatedBy: invalidCharacters)
        let joined = components.joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? "名称未設定" : joined
    }
}

private extension Sequence {
    func uniqued<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen: Set<Key> = []
        return filter { seen.insert(key($0)).inserted }
    }
}
