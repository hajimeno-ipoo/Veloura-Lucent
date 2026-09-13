import SwiftUI

public struct ExpandedBlossomView: View {
  @Bindable var model: BlossomColorPickerModel
  let layout: PetalLayout
  let recentColors: [Color]
  let onSampleColor: () -> Void

  @Environment(\.blossomStyle) private var style

  public init(
    model: BlossomColorPickerModel,
    layout: PetalLayout,
    recentColors: [Color] = [],
    onSampleColor: @escaping () -> Void = {}
  ) {
    self.model = model
    self.layout = layout
    self.recentColors = recentColors
    self.onSampleColor = onSampleColor
  }

  public var body: some View {
    let ringRadius = layout.outerRadius + style.petalSize / 2 + BlossomConstants.outerRingInset
    let sliderRadius = ringRadius + style.sliderWidth / 2 + BlossomConstants.sliderPadding
    let flowerSize = Self.flowerSize(layout: layout, style: style)
    let flowerCenter = CGPoint(x: flowerSize / 2, y: flowerSize / 2)

    VStack(spacing: BlossomConstants.utilityBarSpacing) {
      ZStack {
        // Outer ring (always shows selected color, not hovered color)
        OuterRingView(
          color: model.selectedColor,
          radius: ringRadius,
          isExpanded: model.isExpanded
        )

        // Blossom petals
        BlossomPetalsView(
          model: model,
          layout: layout,
          center: flowerCenter
        )
        .frame(width: flowerSize, height: flowerSize)

        // Center circle (fixed color from JSON, tap to select or close if already selected)
        // Appears first on expand, disappears last on collapse
        CenterCircleView(
          centerColor: layout.centerColor,
          isExpanded: model.isExpanded,
          expandDelay: 0,
          collapseDelay: Double(layout.totalPetalCount) * BlossomConstants.petalAnimationDelay
        )

        // Arc slider on the right
        ArcSliderView(model: model, radius: sliderRadius)

        // Opacity uses the matching left arc without changing the original flower size.
        if model.supportsOpacity {
          OpacityArcSliderView(model: model, radius: sliderRadius)
        }
      }
      .frame(width: flowerSize, height: flowerSize)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            if let (index, ring) = layout.petalIndex(
              at: value.location,
              center: flowerCenter,
              petalSize: style.petalSize
            ) {
              if model.hoveredPetalIndex != index || model.hoveredRing != ring {
                model.hoveredPetalIndex = index
                model.hoveredRing = ring
              }
            } else {
              model.hoveredPetalIndex = nil
              model.hoveredRing = nil
            }
          }
          .onEnded { value in
            let dx = value.location.x - flowerCenter.x
            let dy = value.location.y - flowerCenter.y
            let distance = sqrt(dx * dx + dy * dy)

            if distance <= style.centerCircleSize / 2 {
              let tappedColor = layout.centerColor
              if colorsMatch(tappedColor, model.selectedColor) {
                model.collapse()
              } else {
                model.selectCenterColor(layout: layout)
              }
            } else if let (index, ring) = layout.petalIndex(
              at: value.location,
              center: flowerCenter,
              petalSize: style.petalSize
            ) {
              let tappedColor = layout.color(for: index, ring: ring)
              if colorsMatch(tappedColor, model.selectedColor) {
                model.collapse()
              } else {
                model.selectPetal(index: index, ring: ring, layout: layout)
              }
            }

            model.hoveredPetalIndex = nil
            model.hoveredRing = nil
          }
      )
      .onContinuousHover { phase in
        switch phase {
        case .active(let location):
          if let (index, ring) = layout.petalIndex(
            at: location,
            center: flowerCenter,
            petalSize: style.petalSize
          ) {
            model.hoveredPetalIndex = index
            model.hoveredRing = ring
          } else {
            model.hoveredPetalIndex = nil
            model.hoveredRing = nil
          }
        case .ended:
          model.hoveredPetalIndex = nil
          model.hoveredRing = nil
        }
      }

      utilityBar
    }
    .overlay(alignment: .top) {
      windowDragHandle
    }
  }

  private var windowDragHandle: some View {
    ZStack {
      Circle()
        .fill(.secondary.opacity(0.55))
        .overlay {
          Circle()
            .stroke(.white.opacity(0.35), lineWidth: BlossomConstants.borderWidth)
        }
        .frame(
          width: BlossomConstants.recentColorSwatchSize,
          height: BlossomConstants.recentColorSwatchSize
        )
    }
    .frame(
      width: BlossomConstants.utilityButtonSize,
      height: BlossomConstants.utilityButtonSize
    )
    .contentShape(Circle())
    .gesture(WindowDragGesture())
    .allowsWindowActivationEvents()
    .help("ドラッグして移動")
  }

  private var utilityBar: some View {
    HStack(spacing: 4) {
      Button(action: onSampleColor) {
        Image(systemName: "eyedropper")
          .frame(
            width: BlossomConstants.utilityButtonSize,
            height: BlossomConstants.utilityButtonSize
          )
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .help("画面から色を選ぶ")
      .accessibilityLabel("スポイト")

      ForEach(
        Array(recentColors.prefix(BlossomConstants.recentColorLimit).enumerated()), id: \.offset
      ) { index, color in
        Button {
          if recentColorMatchesSelection(color) {
            model.collapse()
          } else {
            model.selectRecentColor(color)
          }
        } label: {
          Circle()
            .fill(color)
            .overlay {
              Circle()
                .stroke(.white.opacity(0.55), lineWidth: BlossomConstants.borderWidth)
            }
            .frame(
              width: BlossomConstants.recentColorSwatchSize,
              height: BlossomConstants.recentColorSwatchSize
            )
            .frame(
              width: BlossomConstants.recentColorButtonSize,
              height: BlossomConstants.recentColorButtonSize
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("最近使った色 \(index + 1)")
        .accessibilityLabel("最近使った色 \(index + 1)")
      }

      Spacer(minLength: 0)

      Button {
        model.collapse()
      } label: {
        Image(systemName: "xmark")
          .frame(
            width: BlossomConstants.utilityButtonSize,
            height: BlossomConstants.utilityButtonSize
          )
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .help("カラーピッカーを閉じる")
      .accessibilityLabel("カラーピッカーを閉じる")
    }
    .padding(.horizontal, BlossomConstants.utilityBarHorizontalPadding)
    .frame(
      width: BlossomConstants.utilityBarWidth,
      height: BlossomConstants.utilityBarHeight
    )
    .background(.thinMaterial, in: Capsule())
    .contentShape(Capsule())
    .opacity(model.isExpanded ? 1 : 0)
    .scaleEffect(model.isExpanded ? 1 : 0.85)
    .allowsHitTesting(model.isExpanded)
    .animation(.blossom(delay: BlossomConstants.arcSliderAnimationDelay), value: model.isExpanded)
  }

  private func recentColorMatchesSelection(_ color: Color) -> Bool {
    guard colorsMatch(color, model.selectedColor) else { return false }
    guard model.supportsOpacity else { return true }
    return abs(extractOpacity(from: color) - model.opacity) < 0.01
  }

  public static func flowerSize(layout: PetalLayout, style: BlossomStyle = .default) -> CGFloat {
    let ringRadius = layout.outerRadius + style.petalSize / 2 + BlossomConstants.outerRingInset
    let sliderRadius = ringRadius + style.sliderWidth / 2 + BlossomConstants.sliderPadding
    return sliderRadius * 2 + style.sliderWidth + BlossomConstants.viewPadding
  }

  /// Calculate the total size needed for the flower and utility bar.
  public static func totalSize(layout: PetalLayout, style: BlossomStyle = .default) -> CGSize {
    let flowerSize = flowerSize(layout: layout, style: style)
    return CGSize(
      width: max(flowerSize, BlossomConstants.utilityBarWidth),
      height: flowerSize + BlossomConstants.utilityBarSpacing + BlossomConstants.utilityBarHeight
    )
  }
}

#Preview {
  @Previewable @State var model = BlossomColorPickerModel(
    initialColor: .green, supportsOpacity: true)

  ExpandedBlossomView(
    model: model,
    layout: PetalLayout()
  )
  .onAppear {
    model.expand()
  }
  .padding(40)
}
