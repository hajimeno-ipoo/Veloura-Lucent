import AppKit
import SwiftUI

struct WaveformTrackResizeHandle: View {
    static let minimumHeight: CGFloat = 68
    static let defaultHeight: CGFloat = 96
    static let maximumHeight: CGFloat = 192

    let title: String
    @Binding var height: CGFloat
    @State private var dragStartHeight: CGFloat?
    @State private var isHovered = false

    var body: some View {
        Capsule()
            .fill(.secondary.opacity(isHovered ? 0.34 : 0.16))
            .frame(width: 46, height: 3)
            .frame(maxWidth: .infinity)
            .frame(height: 10)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isHovered = true
                    NSCursor.resizeUpDown.set()
                case .ended:
                    isHovered = false
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: .global
                )
                    .onChanged { value in
                        if dragStartHeight == nil {
                            dragStartHeight = height
                        }
                        guard let dragStartHeight else { return }
                        height = Self.resizedHeight(
                            from: dragStartHeight,
                            verticalTranslation: value.translation.height
                        )
                    }
                    .onEnded { value in
                        guard let dragStartHeight else { return }
                        height = Self.resizedHeight(
                            from: dragStartHeight,
                            verticalTranslation: value.translation.height
                        )
                        self.dragStartHeight = nil
                    }
            )
            .accessibilityLabel("\(title)の波形トラックの高さ")
            .accessibilityValue("\(Int(height.rounded()))ポイント")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    height = Self.clampedHeight(height + 8)
                case .decrement:
                    height = Self.clampedHeight(height - 8)
                @unknown default:
                    break
                }
            }
    }

    static func clampedHeight(_ proposedHeight: CGFloat) -> CGFloat {
        min(
            max(proposedHeight, minimumHeight),
            maximumHeight
        )
    }

    static func resizedHeight(
        from startHeight: CGFloat,
        verticalTranslation: CGFloat
    ) -> CGFloat {
        clampedHeight(startHeight + verticalTranslation)
    }
}
