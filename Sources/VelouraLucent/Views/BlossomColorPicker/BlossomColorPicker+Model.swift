import SwiftUI

@Observable
@MainActor
public final class BlossomColorPickerModel {
    public var selectedColor: Color {
        didSet {
            updateFromColor()
        }
    }

    /// Hue in degrees (0-360)
    public private(set) var hue: Double
    /// Saturation (0-1)
    public private(set) var saturation: Double
    /// Lightness/Brightness (0-100)
    public private(set) var lightness: Double
    /// Opacity (0-1)
    public private(set) var opacity: Double

    public let supportsOpacity: Bool
    public var isExpanded: Bool = false
    public var hoveredPetalIndex: Int?
    public var hoveredRing: PetalLayout.Ring?

    private var isUpdatingInternally = false

    public init(initialColor: Color = .blue, supportsOpacity: Bool = false) {
        selectedColor = initialColor
        let (h, s, b) = extractHSB(from: initialColor)
        hue = h
        saturation = s
        lightness = b
        opacity = supportsOpacity ? extractOpacity(from: initialColor) : 1
        self.supportsOpacity = supportsOpacity
    }

    private func updateFromColor() {
        guard !isUpdatingInternally else { return }
        let (h, s, b) = extractHSB(from: selectedColor)
        hue = h
        saturation = s
        lightness = b
        if supportsOpacity {
            opacity = extractOpacity(from: selectedColor)
        }
    }

    public func updateHue(_ newHue: Double) {
        isUpdatingInternally = true
        hue = newHue.truncatingRemainder(dividingBy: 360.0)
        if hue < 0 { hue += 360 }
        selectedColor = resolvedColor()
        isUpdatingInternally = false
    }

    public func updateSaturation(_ newSaturation: Double) {
        isUpdatingInternally = true
        saturation = max(0, min(1, newSaturation))
        selectedColor = resolvedColor()
        isUpdatingInternally = false
    }

    public func updateLightness(_ newLightness: Double) {
        isUpdatingInternally = true
        lightness = max(0, min(100, newLightness))
        selectedColor = resolvedColor()
        isUpdatingInternally = false
    }

    public func updateOpacity(_ newOpacity: Double) {
        guard supportsOpacity else { return }
        isUpdatingInternally = true
        opacity = max(0, min(1, newOpacity))
        selectedColor = resolvedColor()
        isUpdatingInternally = false
    }

    public func selectPetal(index: Int, ring: PetalLayout.Ring, layout: PetalLayout) {
        let color = layout.color(for: index, ring: ring)
        selectColor(color)
    }

    public func selectCenterColor(layout: PetalLayout) {
        selectColor(layout.centerColor)
    }

    public func selectRecentColor(_ color: Color) {
        if supportsOpacity {
            opacity = extractOpacity(from: color)
        }
        selectColor(color)
    }

    public func selectSampledColor(_ color: Color) {
        selectColor(color)
    }

    private func selectColor(_ color: Color) {
        let (h, s, b) = extractHSB(from: color)
        isUpdatingInternally = true
        hue = h
        saturation = s
        lightness = b
        selectedColor = resolvedColor()
        isUpdatingInternally = false
    }

    private func resolvedColor() -> Color {
        Color(
            hue: hue / 360.0,
            saturation: saturation,
            brightness: lightness / 100.0,
            opacity: supportsOpacity ? opacity : 1
        )
    }

    public func outerRingColor(layout: PetalLayout) -> Color {
        guard let index = hoveredPetalIndex, let ring = hoveredRing else {
            return selectedColor
        }
        return layout.color(for: index, ring: ring)
    }

    public func expand() {
        isExpanded = true
    }

    public func collapse() {
        isExpanded = false
        hoveredPetalIndex = nil
        hoveredRing = nil
    }

    public func toggle() {
        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }
}
