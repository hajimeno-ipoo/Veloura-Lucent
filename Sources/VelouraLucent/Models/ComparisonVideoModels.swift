import AppKit
import CoreGraphics
import Foundation
import Observation
import UniformTypeIdentifiers

struct ComparisonVideoSource: Identifiable, Sendable {
    let id: String
    let fileURL: URL
    let trackTitle: String
    let roleTitle: String
    let inspectorMetrics: AudioMetricSnapshot?
    private let fingerprint: ComparisonVideoSourceFingerprint?

    init(
        fileURL: URL,
        trackTitle: String,
        roleTitle: String,
        inspectorMetrics: AudioMetricSnapshot? = nil
    ) {
        let normalizedURL = fileURL.standardizedFileURL
        id = normalizedURL.path(percentEncoded: false)
        self.fileURL = normalizedURL
        self.trackTitle = trackTitle
        self.roleTitle = roleTitle
        self.inspectorMetrics = inspectorMetrics
        fingerprint = ComparisonVideoSourceFingerprint.read(from: normalizedURL)
    }

    var matchesCurrentFile: Bool {
        guard let fingerprint else { return false }
        return fingerprint == ComparisonVideoSourceFingerprint.read(from: fileURL)
    }
}

struct ComparisonVideoRGBAColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let defaultBackground = ComparisonVideoRGBAColor(
        red: 0.035,
        green: 0.03,
        blue: 0.05,
        alpha: 1
    )

    static let defaultTitle = ComparisonVideoRGBAColor(
        red: 1,
        green: 1,
        blue: 1,
        alpha: 1
    )

    static let defaultFirstRole = ComparisonVideoRGBAColor(
        red: 0.40,
        green: 0.91,
        blue: 0.98,
        alpha: 1
    )

    static let defaultSecondRole = ComparisonVideoRGBAColor(
        red: 0.94,
        green: 0.67,
        blue: 0.99,
        alpha: 1
    )

    static let defaultVisualizerLeading = ComparisonVideoRGBAColor(
        red: 0.62,
        green: 0.39,
        blue: 0.96,
        alpha: 1
    )

    static let defaultVisualizerCenter = ComparisonVideoRGBAColor(
        red: 0.89,
        green: 0.91,
        blue: 0.38,
        alpha: 1
    )

    static let defaultVisualizerTrailing = ComparisonVideoRGBAColor(
        red: 0.95,
        green: 0.41,
        blue: 0.86,
        alpha: 1
    )
}

enum ComparisonVideoVisualizerPaletteMode: String, CaseIterable, Identifiable, Sendable {
    case standard
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "標準"
        case .custom: "カスタム"
        }
    }
}

struct ComparisonVideoVisualizerGradientStop: Equatable, Sendable {
    let color: ComparisonVideoRGBAColor
    let location: Double
}

final class ComparisonVideoBackgroundImage: @unchecked Sendable {
    let image: NSImage
    let fileName: String

    init(image: NSImage, fileName: String) {
        self.image = image
        self.fileName = fileName
    }
}

enum ComparisonVideoBackgroundImageLayout: String, CaseIterable, Identifiable, Sendable {
    case fill
    case fit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: "画面いっぱい"
        case .fit: "画像全体"
        }
    }
}

enum ComparisonVideoEditableElement: Sendable {
    case title
    case role
    case inspector
    case visualizer
}

enum ComparisonVideoInspectorAspectRatio: String, CaseIterable, Identifiable, Sendable {
    case widescreen
    case standard
    case square
    case portrait
    case vertical
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .widescreen: "16:9"
        case .standard: "4:3"
        case .square: "1:1"
        case .portrait: "3:4"
        case .vertical: "9:16"
        case .custom: "カスタム"
        }
    }

    var fixedValue: Double? {
        switch self {
        case .widescreen: 16.0 / 9.0
        case .standard: 4.0 / 3.0
        case .square: 1
        case .portrait: 3.0 / 4.0
        case .vertical: 9.0 / 16.0
        case .custom: nil
        }
    }
}

enum ComparisonVideoInspectorLayout: Equatable, Sendable {
    case wide
    case square
    case tall

    init(aspectRatio: Double) {
        if aspectRatio > 4.0 / 3.0 {
            self = .wide
        } else if aspectRatio >= 3.0 / 4.0 {
            self = .square
        } else {
            self = .tall
        }
    }

    var columnCount: Int {
        switch self {
        case .wide: 4
        case .square: 2
        case .tall: 1
        }
    }

    var rowCount: Int {
        8 / columnCount
    }

    var horizontalSpacing: CGFloat {
        self == .wide ? 48 : 30
    }

    var verticalSpacing: CGFloat {
        self == .tall ? 12 : 18
    }

    var panelPadding: CGFloat {
        self == .tall ? 24 : 28
    }

    var labelFontSize: CGFloat {
        self == .square ? 28 : 22
    }

    var valueFontSize: CGFloat {
        self == .square ? 32 : 27
    }

}

struct ComparisonVideoDisplaySettings: Sendable {
    static let defaultInspectorSize = CGSize(width: 1_650, height: 220)
    static let minimumInspectorLinearScale = 0.25
    static let fadeDurationRange: ClosedRange<Double> = 0...5
    static let visualizerDimensionRange: ClosedRange<Double> = 0.25...1
    static let visualizerScaleRange: ClosedRange<Double> = 0.25...2

    var trackTitle: String
    var firstRoleTitle: String
    var secondRoleTitle: String
    var titleFontFamily: String?
    var roleFontFamily: String?
    var backgroundColor: ComparisonVideoRGBAColor
    var backgroundImage: ComparisonVideoBackgroundImage?
    var backgroundImageLayout: ComparisonVideoBackgroundImageLayout
    var titleColor: ComparisonVideoRGBAColor
    var firstRoleColor: ComparisonVideoRGBAColor
    var secondRoleColor: ComparisonVideoRGBAColor
    var videoFadeInEnabled: Bool
    var videoFadeOutEnabled: Bool
    var audioFadeInEnabled: Bool
    var audioFadeOutEnabled: Bool
    var visualizerEnabled: Bool
    var visualizerPaletteMode: ComparisonVideoVisualizerPaletteMode
    var visualizerLeadingColor: ComparisonVideoRGBAColor
    var visualizerCenterColor: ComparisonVideoRGBAColor
    var visualizerTrailingColor: ComparisonVideoRGBAColor
    private(set) var inspectorAspectRatio: ComparisonVideoInspectorAspectRatio

    private var storedTitleFontSize: Double
    private var storedRoleFontSize: Double
    private var storedTitlePositionX: Double
    private var storedTitlePositionY: Double
    private var storedRolePositionX: Double
    private var storedRolePositionY: Double
    private var storedInspectorPositionX: Double
    private var storedInspectorPositionY: Double
    private var storedVisualizerPositionX: Double
    private var storedVisualizerPositionY: Double
    private var storedFadeInDuration: Double
    private var storedFadeOutDuration: Double
    private var storedVisualizerWidth: Double
    private var storedVisualizerHeight: Double
    private var storedVisualizerScale: Double
    private var storedCustomAspectWidth: Double
    private var storedCustomAspectHeight: Double
    private var storedInspectorArea: Double

    var titleFontSize: Double {
        get { storedTitleFontSize }
        set { storedTitleFontSize = Self.clampFontSize(newValue, fallback: 82) }
    }

    var roleFontSize: Double {
        get { storedRoleFontSize }
        set { storedRoleFontSize = Self.clampFontSize(newValue, fallback: 64) }
    }

    var titlePositionX: Double {
        get { storedTitlePositionX }
        set { storedTitlePositionX = Self.clampPosition(newValue) }
    }

    var titlePositionY: Double {
        get { storedTitlePositionY }
        set { storedTitlePositionY = Self.clampPosition(newValue) }
    }

    var rolePositionX: Double {
        get { storedRolePositionX }
        set { storedRolePositionX = Self.clampPosition(newValue) }
    }

    var rolePositionY: Double {
        get { storedRolePositionY }
        set { storedRolePositionY = Self.clampPosition(newValue) }
    }

    var inspectorPositionX: Double {
        get { storedInspectorPositionX }
        set { storedInspectorPositionX = Self.clampPosition(newValue) }
    }

    var inspectorPositionY: Double {
        get { storedInspectorPositionY }
        set { storedInspectorPositionY = Self.clampPosition(newValue) }
    }

    var visualizerPositionX: Double {
        get { storedVisualizerPositionX }
        set { storedVisualizerPositionX = Self.clampPosition(newValue) }
    }

    var visualizerPositionY: Double {
        get { storedVisualizerPositionY }
        set { storedVisualizerPositionY = Self.clampPosition(newValue) }
    }

    var fadeInDuration: Double {
        get { storedFadeInDuration }
        set { storedFadeInDuration = Self.clampFadeDuration(newValue) }
    }

    var fadeOutDuration: Double {
        get { storedFadeOutDuration }
        set { storedFadeOutDuration = Self.clampFadeDuration(newValue) }
    }

    var visualizerWidth: Double {
        get { storedVisualizerWidth }
        set { storedVisualizerWidth = Self.clampVisualizerDimension(newValue, fallback: 1) }
    }

    var visualizerHeight: Double {
        get { storedVisualizerHeight }
        set { storedVisualizerHeight = Self.clampVisualizerDimension(newValue, fallback: 0.65) }
    }

    var visualizerScale: Double {
        get { storedVisualizerScale }
        set { storedVisualizerScale = Self.clampVisualizerScale(newValue) }
    }

    var effectiveVideoFadeInDuration: Double {
        videoFadeInEnabled ? fadeInDuration : 0
    }

    var effectiveVideoFadeOutDuration: Double {
        videoFadeOutEnabled ? fadeOutDuration : 0
    }

    var effectiveAudioFadeInDuration: Double {
        audioFadeInEnabled ? fadeInDuration : 0
    }

    var effectiveAudioFadeOutDuration: Double {
        audioFadeOutEnabled ? fadeOutDuration : 0
    }

    init(
        trackTitle: String,
        firstRoleTitle: String,
        secondRoleTitle: String,
        titleFontFamily: String? = nil,
        roleFontFamily: String? = nil,
        titleFontSize: Double = 82,
        roleFontSize: Double = 64,
        titlePositionX: Double = 50,
        titlePositionY: Double = 45,
        rolePositionX: Double = 50,
        rolePositionY: Double = 55,
        inspectorPositionX: Double = 50,
        inspectorPositionY: Double = 84,
        visualizerPositionX: Double = 50,
        visualizerPositionY: Double = 70,
        inspectorWidth: Double = Self.defaultInspectorSize.width,
        inspectorHeight: Double = Self.defaultInspectorSize.height,
        inspectorAspectRatio: ComparisonVideoInspectorAspectRatio = .custom,
        customAspectWidth: Double = 15,
        customAspectHeight: Double = 2,
        titleColor: ComparisonVideoRGBAColor = .defaultTitle,
        firstRoleColor: ComparisonVideoRGBAColor = .defaultFirstRole,
        secondRoleColor: ComparisonVideoRGBAColor = .defaultSecondRole,
        fadeInDuration: Double = 1,
        fadeOutDuration: Double = 1,
        videoFadeInEnabled: Bool = true,
        videoFadeOutEnabled: Bool = true,
        audioFadeInEnabled: Bool = true,
        audioFadeOutEnabled: Bool = true,
        visualizerEnabled: Bool = true,
        visualizerPaletteMode: ComparisonVideoVisualizerPaletteMode = .standard,
        visualizerLeadingColor: ComparisonVideoRGBAColor = .defaultVisualizerLeading,
        visualizerCenterColor: ComparisonVideoRGBAColor = .defaultVisualizerCenter,
        visualizerTrailingColor: ComparisonVideoRGBAColor = .defaultVisualizerTrailing,
        visualizerWidth: Double = 1,
        visualizerHeight: Double = 0.65,
        visualizerScale: Double = 1,
        backgroundColor: ComparisonVideoRGBAColor = .defaultBackground,
        backgroundImage: ComparisonVideoBackgroundImage? = nil,
        backgroundImageLayout: ComparisonVideoBackgroundImageLayout = .fill
    ) {
        self.trackTitle = trackTitle
        self.firstRoleTitle = firstRoleTitle
        self.secondRoleTitle = secondRoleTitle
        self.titleFontFamily = titleFontFamily
        self.roleFontFamily = roleFontFamily
        storedTitleFontSize = Self.clampFontSize(titleFontSize, fallback: 82)
        storedRoleFontSize = Self.clampFontSize(roleFontSize, fallback: 64)
        storedTitlePositionX = Self.clampPosition(titlePositionX)
        storedTitlePositionY = Self.clampPosition(titlePositionY)
        storedRolePositionX = Self.clampPosition(rolePositionX)
        storedRolePositionY = Self.clampPosition(rolePositionY)
        storedInspectorPositionX = Self.clampPosition(inspectorPositionX)
        storedInspectorPositionY = Self.clampPosition(inspectorPositionY)
        storedVisualizerPositionX = Self.clampPosition(visualizerPositionX)
        storedVisualizerPositionY = Self.clampPosition(visualizerPositionY)
        storedFadeInDuration = Self.clampFadeDuration(fadeInDuration)
        storedFadeOutDuration = Self.clampFadeDuration(fadeOutDuration)
        storedVisualizerWidth = Self.clampVisualizerDimension(visualizerWidth, fallback: 1)
        storedVisualizerHeight = Self.clampVisualizerDimension(visualizerHeight, fallback: 0.65)
        storedVisualizerScale = Self.clampVisualizerScale(visualizerScale)
        self.inspectorAspectRatio = inspectorAspectRatio
        storedCustomAspectWidth = Self.validAspectComponent(customAspectWidth) ?? 15
        storedCustomAspectHeight = Self.validAspectComponent(customAspectHeight) ?? 2
        let validWidth = Self.finiteValue(inspectorWidth, fallback: Self.defaultInspectorSize.width)
        let validHeight = Self.finiteValue(inspectorHeight, fallback: Self.defaultInspectorSize.height)
        storedInspectorArea = max(validWidth * validHeight, 1)
        self.titleColor = titleColor
        self.firstRoleColor = firstRoleColor
        self.secondRoleColor = secondRoleColor
        self.videoFadeInEnabled = videoFadeInEnabled
        self.videoFadeOutEnabled = videoFadeOutEnabled
        self.audioFadeInEnabled = audioFadeInEnabled
        self.audioFadeOutEnabled = audioFadeOutEnabled
        self.visualizerEnabled = visualizerEnabled
        self.visualizerPaletteMode = visualizerPaletteMode
        self.visualizerLeadingColor = visualizerLeadingColor
        self.visualizerCenterColor = visualizerCenterColor
        self.visualizerTrailingColor = visualizerTrailingColor
        self.backgroundColor = backgroundColor
        self.backgroundImage = backgroundImage
        self.backgroundImageLayout = backgroundImageLayout
    }

    var visualizerGradientStops: [ComparisonVideoVisualizerGradientStop] {
        switch visualizerPaletteMode {
        case .standard:
            Self.standardVisualizerGradientStops
        case .custom:
            [
                ComparisonVideoVisualizerGradientStop(
                    color: visualizerLeadingColor,
                    location: 0
                ),
                ComparisonVideoVisualizerGradientStop(
                    color: visualizerCenterColor,
                    location: 0.5
                ),
                ComparisonVideoVisualizerGradientStop(
                    color: visualizerTrailingColor,
                    location: 1
                )
            ]
        }
    }

    private static let standardVisualizerGradientStops: [ComparisonVideoVisualizerGradientStop] = [
        ComparisonVideoVisualizerGradientStop(
            color: ComparisonVideoRGBAColor(red: 166.0 / 255, green: 140.0 / 255, blue: 249.0 / 255, alpha: 1),
            location: 0
        ),
        ComparisonVideoVisualizerGradientStop(
            color: ComparisonVideoRGBAColor(red: 90.0 / 255, green: 165.0 / 255, blue: 246.0 / 255, alpha: 1),
            location: 1.0 / 6
        ),
        ComparisonVideoVisualizerGradientStop(
            color: ComparisonVideoRGBAColor(red: 89.0 / 255, green: 193.0 / 255, blue: 227.0 / 255, alpha: 1),
            location: 2.0 / 6
        ),
        ComparisonVideoVisualizerGradientStop(
            color: ComparisonVideoRGBAColor(red: 107.0 / 255, green: 223.0 / 255, blue: 99.0 / 255, alpha: 1),
            location: 3.0 / 6
        ),
        ComparisonVideoVisualizerGradientStop(
            color: ComparisonVideoRGBAColor(red: 216.0 / 255, green: 240.0 / 255, blue: 101.0 / 255, alpha: 1),
            location: 4.0 / 6
        ),
        ComparisonVideoVisualizerGradientStop(
            color: ComparisonVideoRGBAColor(red: 236.0 / 255, green: 167.0 / 255, blue: 91.0 / 255, alpha: 1),
            location: 5.0 / 6
        ),
        ComparisonVideoVisualizerGradientStop(
            color: ComparisonVideoRGBAColor(red: 227.0 / 255, green: 80.0 / 255, blue: 188.0 / 255, alpha: 1),
            location: 1
        )
    ]

    func position(for element: ComparisonVideoEditableElement) -> CGPoint {
        switch element {
        case .title:
            CGPoint(x: titlePositionX, y: titlePositionY)
        case .role:
            CGPoint(x: rolePositionX, y: rolePositionY)
        case .inspector:
            CGPoint(x: inspectorPositionX, y: inspectorPositionY)
        case .visualizer:
            CGPoint(x: visualizerPositionX, y: visualizerPositionY)
        }
    }

    mutating func setPosition(_ position: CGPoint, for element: ComparisonVideoEditableElement) {
        switch element {
        case .title:
            titlePositionX = position.x
            titlePositionY = position.y
        case .role:
            rolePositionX = position.x
            rolePositionY = position.y
        case .inspector:
            inspectorPositionX = position.x
            inspectorPositionY = position.y
        case .visualizer:
            visualizerPositionX = position.x
            visualizerPositionY = position.y
        }
    }

    func visualizerSize(for orientation: ComparisonVideoOrientation) -> CGSize {
        return CGSize(
            width: orientation.pixelSize.width * visualizerWidth * visualizerScale,
            height: orientation.pixelSize.height * 0.14 * visualizerHeight * visualizerScale
        )
    }

    mutating func updateInspectorDefaultPosition(
        from oldOrientation: ComparisonVideoOrientation,
        to newOrientation: ComparisonVideoOrientation
    ) {
        let oldDefault = Self.defaultInspectorPosition(for: oldOrientation)
        let newDefault = Self.defaultInspectorPosition(for: newOrientation)

        if inspectorPositionX == oldDefault.x {
            inspectorPositionX = newDefault.x
        }
        if inspectorPositionY == oldDefault.y {
            inspectorPositionY = newDefault.y
        }
    }

    static func defaultInspectorPosition(
        for orientation: ComparisonVideoOrientation
    ) -> CGPoint {
        switch orientation {
        case .landscape:
            CGPoint(x: 50, y: 84)
        case .portrait:
            CGPoint(x: 50, y: 80)
        }
    }

    func inspectorSize(for orientation: ComparisonVideoOrientation) -> CGSize {
        let maximumArea = maximumInspectorArea(for: orientation)
        return Self.inspectorSize(
            area: min(
                max(storedInspectorArea, min(Self.minimumInspectorArea, maximumArea)),
                maximumArea
            ),
            aspectRatio: inspectorAspectValue
        )
    }

    func inspectorContentScale(for orientation: ComparisonVideoOrientation) -> Double {
        let size = inspectorSize(for: orientation)
        let actualArea = size.width * size.height
        let referenceArea = min(
            Self.defaultInspectorSize.width * Self.defaultInspectorSize.height,
            maximumInspectorArea(for: orientation)
        )
        return max(sqrt(actualArea / referenceArea), 0.001)
    }

    var inspectorAspectValue: Double {
        inspectorAspectRatio.fixedValue
            ?? storedCustomAspectWidth / storedCustomAspectHeight
    }

    var inspectorLayout: ComparisonVideoInspectorLayout {
        ComparisonVideoInspectorLayout(aspectRatio: inspectorAspectValue)
    }

    var customAspectWidth: Double { storedCustomAspectWidth }
    var customAspectHeight: Double { storedCustomAspectHeight }

    mutating func setInspectorAspectRatio(
        _ aspectRatio: ComparisonVideoInspectorAspectRatio,
        for orientation: ComparisonVideoOrientation
    ) {
        inspectorAspectRatio = aspectRatio
        clampInspectorArea(for: orientation)
    }

    mutating func setCustomAspectWidth(
        _ value: Double,
        for orientation: ComparisonVideoOrientation
    ) {
        guard let value = Self.validAspectComponent(value) else { return }
        storedCustomAspectWidth = value
        clampInspectorArea(for: orientation)
    }

    mutating func setCustomAspectHeight(
        _ value: Double,
        for orientation: ComparisonVideoOrientation
    ) {
        guard let value = Self.validAspectComponent(value) else { return }
        storedCustomAspectHeight = value
        clampInspectorArea(for: orientation)
    }

    func inspectorScale(for orientation: ComparisonVideoOrientation) -> Double {
        sqrt(min(storedInspectorArea, maximumInspectorArea(for: orientation)))
    }

    func inspectorScaleRange(for orientation: ComparisonVideoOrientation) -> ClosedRange<Double> {
        let maximumArea = maximumInspectorArea(for: orientation)
        return sqrt(min(Self.minimumInspectorArea, maximumArea))...sqrt(maximumArea)
    }

    mutating func setInspectorScale(
        _ scale: Double,
        for orientation: ComparisonVideoOrientation
    ) {
        let range = inspectorScaleRange(for: orientation)
        let finiteScale = Self.finiteValue(scale, fallback: range.lowerBound)
        let clampedScale = min(max(finiteScale, range.lowerBound), range.upperBound)
        storedInspectorArea = clampedScale * clampedScale
    }

    private mutating func clampInspectorArea(for orientation: ComparisonVideoOrientation) {
        let maximumArea = maximumInspectorArea(for: orientation)
        storedInspectorArea = min(
            max(storedInspectorArea, min(Self.minimumInspectorArea, maximumArea)),
            maximumArea
        )
    }

    private static var minimumInspectorArea: Double {
        defaultInspectorSize.width
            * defaultInspectorSize.height
            * minimumInspectorLinearScale
            * minimumInspectorLinearScale
    }

    private func maximumInspectorArea(for orientation: ComparisonVideoOrientation) -> Double {
        let ratio = inspectorAspectValue
        let maximumWidth = orientation.pixelSize.width * 0.88
        let maximumHeight = orientation.pixelSize.height * 0.88
        let widthLimitedHeight = maximumWidth / ratio
        let maximumSize: CGSize
        if widthLimitedHeight <= maximumHeight {
            maximumSize = CGSize(width: maximumWidth, height: widthLimitedHeight)
        } else {
            maximumSize = CGSize(width: maximumHeight * ratio, height: maximumHeight)
        }
        return maximumSize.width * maximumSize.height
    }

    private static func inspectorSize(area: Double, aspectRatio: Double) -> CGSize {
        CGSize(
            width: sqrt(area * aspectRatio),
            height: sqrt(area / aspectRatio)
        )
    }

    private static func clampFontSize(_ value: Double, fallback: Double) -> Double {
        min(max(value.isFinite ? value : fallback, 24), 300)
    }

    private static func clampPosition(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 50, 0), 100)
    }

    private static func clampFadeDuration(_ value: Double) -> Double {
        let finiteValue = value.isFinite ? value : 1
        return min(max(finiteValue, fadeDurationRange.lowerBound), fadeDurationRange.upperBound)
    }

    private static func clampVisualizerDimension(_ value: Double, fallback: Double) -> Double {
        let finiteValue = value.isFinite ? value : fallback
        return min(
            max(finiteValue, visualizerDimensionRange.lowerBound),
            visualizerDimensionRange.upperBound
        )
    }

    private static func clampVisualizerScale(_ value: Double) -> Double {
        let finiteValue = value.isFinite ? value : 1
        return min(
            max(finiteValue, visualizerScaleRange.lowerBound),
            visualizerScaleRange.upperBound
        )
    }

    private static func finiteValue(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }

    private static func validAspectComponent(_ value: Double) -> Double? {
        guard value.isFinite, value > 0 else { return nil }
        return min(value, 10_000)
    }
}

struct ComparisonVideoInspectorInfo: Sendable {
    let metrics: AudioMetricSnapshot?
    let fileInfo: AudioFileInfo?
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

    func previewFrameTime(at outputTime: TimeInterval) -> TimeInterval {
        let location = segment(at: outputTime)
        let segmentStart = segments[..<location.index].reduce(0) { elapsed, segment in
            elapsed + segment.duration
        }
        let transitionDuration = min(0.3, location.segment.duration)
        return segmentStart + min(location.localTime, transitionDuration)
    }
}

struct ComparisonVideoFrameState: Sendable {
    let displaySettings: ComparisonVideoDisplaySettings
    let firstInspectorInfo: ComparisonVideoInspectorInfo?
    let secondInspectorInfo: ComparisonVideoInspectorInfo?
    let plan: ComparisonVideoPlan
    let outputTime: TimeInterval
    let effectsTime: TimeInterval
    let visualizerSpectrum: ComparisonVideoSpectrumFrame

    init(
        displaySettings: ComparisonVideoDisplaySettings,
        firstInspectorInfo: ComparisonVideoInspectorInfo?,
        secondInspectorInfo: ComparisonVideoInspectorInfo?,
        plan: ComparisonVideoPlan,
        outputTime: TimeInterval,
        effectsTime: TimeInterval? = nil,
        visualizerSpectrum: ComparisonVideoSpectrumFrame = .empty
    ) {
        self.displaySettings = displaySettings
        self.firstInspectorInfo = firstInspectorInfo
        self.secondInspectorInfo = secondInspectorInfo
        self.plan = plan
        self.outputTime = outputTime
        self.effectsTime = effectsTime ?? outputTime
        self.visualizerSpectrum = visualizerSpectrum
    }

    init(
        trackTitle: String,
        firstRoleTitle: String,
        secondRoleTitle: String,
        plan: ComparisonVideoPlan,
        outputTime: TimeInterval
    ) {
        self.init(
            displaySettings: ComparisonVideoDisplaySettings(
                trackTitle: trackTitle,
                firstRoleTitle: firstRoleTitle,
                secondRoleTitle: secondRoleTitle
            ),
            firstInspectorInfo: nil,
            secondInspectorInfo: nil,
            plan: plan,
            outputTime: outputTime
        )
    }

    var trackTitle: String { displaySettings.trackTitle }
    var firstRoleTitle: String { displaySettings.firstRoleTitle }
    var secondRoleTitle: String { displaySettings.secondRoleTitle }

    var activeSourceIndex: Int {
        plan.segment(at: outputTime).segment.sourceIndex
    }

    var activeRoleTitle: String {
        activeSourceIndex == 0 ? firstRoleTitle : secondRoleTitle
    }

    var activeInspectorInfo: ComparisonVideoInspectorInfo? {
        activeSourceIndex == 0 ? firstInspectorInfo : secondInspectorInfo
    }

    var transitionProgress: Double {
        let location = plan.segment(at: outputTime)
        let transitionDuration = min(0.3, location.segment.duration)
        guard transitionDuration > 0 else { return 1 }
        return min(max(location.localTime / transitionDuration, 0), 1)
    }

    var videoFadeLevel: Double {
        ComparisonVideoFadeEnvelope.level(
            at: effectsTime,
            duration: plan.outputDuration,
            fadeInDuration: displaySettings.effectiveVideoFadeInDuration,
            fadeOutDuration: displaySettings.effectiveVideoFadeOutDuration
        )
    }
}

enum ComparisonVideoFadeEnvelope {
    static func level(
        at time: TimeInterval,
        duration: TimeInterval,
        fadeInDuration: TimeInterval,
        fadeOutDuration: TimeInterval
    ) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        let clampedTime = min(max(time.isFinite ? time : 0, 0), duration)
        let fadeInLevel = fadeInDuration > 0
            ? min(max(clampedTime / fadeInDuration, 0), 1)
            : 1
        let fadeOutLevel = fadeOutDuration > 0
            ? min(max((duration - clampedTime) / fadeOutDuration, 0), 1)
            : 1
        return min(fadeInLevel, fadeOutLevel)
    }
}

struct ComparisonVideoSpectrumFrame: Sendable {
    static let empty = ComparisonVideoSpectrumFrame(points: [], peakLevelsDB: [])

    let points: [RealtimeSpectrumPoint]
    let peakLevelsDB: [Double]
}

enum ComparisonVideoSpectrumProcessor {
    static let frequencyCount = 48
    static let peakHoldDuration: TimeInterval = 0.4
    static let levelDecayDBPerSecond = 24.0
    static let peakDecayDBPerSecond = 18.0

    static let frequencies: [Double] = (0..<frequencyCount).map { index in
        let progress = Double(index) / Double(frequencyCount - 1)
        return 80 * pow(20_000.0 / 80.0, progress)
    }

    static func frames(
        from rawTimeline: [[RealtimeSpectrumPoint]],
        interval: TimeInterval
    ) -> [ComparisonVideoSpectrumFrame] {
        guard !rawTimeline.isEmpty, interval > 0 else { return [] }
        let silentPoints = frequencies.enumerated().map { index, frequency in
            RealtimeSpectrumPoint(
                id: "comparison-\(index)",
                frequencyHz: frequency,
                levelDB: -100
            )
        }
        var smoothedLevels = Array(repeating: -100.0, count: frequencyCount)
        var peakLevels = smoothedLevels
        var peakHoldFramesRemaining = Array(repeating: 0, count: frequencyCount)
        let peakHoldFrameCount = Int(ceil(peakHoldDuration / interval))
        let levelDecay = levelDecayDBPerSecond * interval
        let peakDecay = peakDecayDBPerSecond * interval

        return rawTimeline.map { rawPoints in
            let points = frequencies.indices.map { index in
                index < rawPoints.count ? rawPoints[index] : silentPoints[index]
            }
            for index in 0..<frequencyCount {
                let rawLevel = min(max(points[index].levelDB, -100), 0)
                smoothedLevels[index] = max(rawLevel, smoothedLevels[index] - levelDecay)

                if smoothedLevels[index] >= peakLevels[index] {
                    peakLevels[index] = smoothedLevels[index]
                    peakHoldFramesRemaining[index] = peakHoldFrameCount
                } else if peakHoldFramesRemaining[index] > 0 {
                    peakHoldFramesRemaining[index] -= 1
                } else {
                    peakLevels[index] = max(
                        smoothedLevels[index],
                        peakLevels[index] - peakDecay
                    )
                }
            }

            return ComparisonVideoSpectrumFrame(
                points: zip(points, smoothedLevels).enumerated().map { index, pair in
                    RealtimeSpectrumPoint(
                        id: "comparison-\(index)",
                        frequencyHz: pair.0.frequencyHz,
                        levelDB: pair.1
                    )
                },
                peakLevelsDB: peakLevels
            )
        }
    }
}

struct ComparisonVideoSpectrumDotGeometry: Sendable {
    let inactiveDots: [CGRect]
    let lowDots: [CGRect]
    let middleDots: [CGRect]
    let highDots: [CGRect]
    let innerGlowDots: [CGRect]
    let outerGlowDots: [CGRect]
    let peakDots: [CGRect]
    let peakGlowDots: [CGRect]
    let reflectionDots: [CGRect]
}

enum ComparisonVideoSpectrumGeometry {
    static let dotRowCount = 10

    static func dots(
        for frame: ComparisonVideoSpectrumFrame,
        in size: CGSize
    ) -> ComparisonVideoSpectrumDotGeometry {
        let points = frame.points
        guard !points.isEmpty, size.width > 0, size.height > 0 else {
            return ComparisonVideoSpectrumDotGeometry(
                inactiveDots: [],
                lowDots: [],
                middleDots: [],
                highDots: [],
                innerGlowDots: [],
                outerGlowDots: [],
                peakDots: [],
                peakGlowDots: [],
                reflectionDots: []
            )
        }

        let mainHeight = size.height * 0.78
        let reflectionStart = size.height * 0.82
        let reflectionHeight = size.height - reflectionStart
        let columnStep = size.width / CGFloat(points.count)
        let rowStep = mainHeight / CGFloat(dotRowCount)
        let diameter = max(min(columnStep * 0.44, rowStep * 0.62), 1)
        let reflectionStep = reflectionHeight / 3

        var inactiveDots: [CGRect] = []
        var lowDots: [CGRect] = []
        var middleDots: [CGRect] = []
        var highDots: [CGRect] = []
        var innerGlowDots: [CGRect] = []
        var outerGlowDots: [CGRect] = []
        var peakDots: [CGRect] = []
        var peakGlowDots: [CGRect] = []
        var reflectionDots: [CGRect] = []
        inactiveDots.reserveCapacity(points.count * dotRowCount)

        for (index, point) in points.enumerated() {
            let centerX = (CGFloat(index) + 0.5) * columnStep
            let activeCount = min(
                Int(ceil(normalizedLevel(for: point.levelDB) * Double(dotRowCount))),
                dotRowCount
            )
            let peakLevel = index < frame.peakLevelsDB.count
                ? frame.peakLevelsDB[index]
                : point.levelDB
            let peakCount = min(
                Int(ceil(normalizedLevel(for: peakLevel) * Double(dotRowCount))),
                dotRowCount
            )

            for row in 0..<dotRowCount {
                let centerY = mainHeight - (CGFloat(row) + 0.5) * rowStep
                let dot = CGRect(
                    x: centerX - diameter / 2,
                    y: centerY - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                guard row < activeCount else {
                    inactiveDots.append(dot)
                    continue
                }

                let progress = Double(row) / Double(max(dotRowCount - 1, 1))
                if progress < 0.34 {
                    lowDots.append(dot)
                } else if progress < 0.67 {
                    middleDots.append(dot)
                } else {
                    highDots.append(dot)
                }
                innerGlowDots.append(dot.insetBy(dx: -diameter * 0.34, dy: -diameter * 0.34))
                outerGlowDots.append(dot.insetBy(dx: -diameter * 0.72, dy: -diameter * 0.72))
            }

            if peakCount > 0 {
                let row = peakCount - 1
                let centerY = mainHeight - (CGFloat(row) + 0.5) * rowStep
                let peakDot = CGRect(
                    x: centerX - diameter / 2,
                    y: centerY - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                peakDots.append(peakDot)
                peakGlowDots.append(
                    peakDot.insetBy(dx: -diameter * 0.95, dy: -diameter * 0.95)
                )
            }

            let reflectedCount = min(activeCount, 3)
            for row in 0..<reflectedCount {
                let reflectionDiameter = diameter * (0.82 - CGFloat(row) * 0.16)
                let centerY = reflectionStart + (CGFloat(row) + 0.5) * reflectionStep
                reflectionDots.append(CGRect(
                    x: centerX - reflectionDiameter / 2,
                    y: centerY - reflectionDiameter / 2,
                    width: reflectionDiameter,
                    height: reflectionDiameter
                ))
            }
        }

        return ComparisonVideoSpectrumDotGeometry(
            inactiveDots: inactiveDots,
            lowDots: lowDots,
            middleDots: middleDots,
            highDots: highDots,
            innerGlowDots: innerGlowDots,
            outerGlowDots: outerGlowDots,
            peakDots: peakDots,
            peakGlowDots: peakGlowDots,
            reflectionDots: reflectionDots
        )
    }

    private static func normalizedLevel(for levelDB: Double) -> Double {
        min(max((levelDB + 80) / 80, 0), 1)
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
                requiresPreviewOwnership: false,
                inspectorMetrics: job.inputMetrics
            ),
            source(
                url: job.hasExistingOutput ? job.outputFile : nil,
                title: title,
                role: "補正後",
                requiresPreviewOwnership: true,
                inspectorMetrics: job.outputMetrics
            ),
            source(
                url: job.hasExistingMasteredOutput ? job.masteredOutputFile : nil,
                title: title,
                role: "最終版",
                requiresPreviewOwnership: true,
                inspectorMetrics: job.masteredMetrics
            ),
        ].compactMap { $0 }
    }

    @MainActor
    static func stem(model: StemModeWorkspaceModel) -> [ComparisonVideoSource] {
        stem(
            selectedInputURL: model.selectedInputURL,
            artifactStates: model.session.artifactStates
        ).map { source in
            let metrics: AudioMetricSnapshot?
            if source.fileURL == model.selectedInputURL?.standardizedFileURL {
                metrics = model.inputMetrics
            } else if let kind = model.session.artifactStates.first(where: {
                $0.artifact?.fileURL.standardizedFileURL == source.fileURL
            })?.kind {
                metrics = inspectorMetrics(for: kind, model: model)
            } else {
                metrics = nil
            }
            return ComparisonVideoSource(
                fileURL: source.fileURL,
                trackTitle: source.trackTitle,
                roleTitle: source.roleTitle,
                inspectorMetrics: metrics
            )
        }
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
        requiresPreviewOwnership: Bool,
        inspectorMetrics: AudioMetricSnapshot? = nil
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
        return ComparisonVideoSource(
            fileURL: normalized,
            trackTitle: title,
            roleTitle: role,
            inspectorMetrics: inspectorMetrics
        )
    }

    @MainActor
    private static func inspectorMetrics(
        for kind: StemArtifactKind,
        model: StemModeWorkspaceModel
    ) -> AudioMetricSnapshot? {
        switch kind {
        case .input44100:
            nil
        case .rawStem(let role):
            model.stemEvaluations.first { $0.role == role }?.rawEvaluation.audioMetrics
        case .correctedStem(let role):
            model.stemEvaluations.first { $0.role == role }?.correctedEvaluation?.audioMetrics
        case .correctedPureSum48000:
            model.remixAnalysisPresentation?.correctedRemixEvaluation.audioMetrics
        case .remixed48000:
            model.remixAnalysisPresentation?.processedRemixEvaluation?.audioMetrics
        case .finalMaster:
            model.finalMetrics
        }
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
