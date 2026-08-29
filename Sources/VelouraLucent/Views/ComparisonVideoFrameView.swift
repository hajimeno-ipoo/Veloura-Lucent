import SwiftUI

struct ComparisonVideoFrameView: View {
    let state: ComparisonVideoFrameState
    let orientation: ComparisonVideoOrientation

    private let firstColor = Color(red: 0.40, green: 0.91, blue: 0.98)
    private let secondColor = Color(red: 0.94, green: 0.67, blue: 0.99)

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = orientation.pixelSize
            let scale = min(
                proxy.size.width / canvasSize.width,
                proxy.size.height / canvasSize.height
            )
            let compact = orientation == .portrait
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.035, green: 0.03, blue: 0.05),
                        Color(red: 0.075, green: 0.055, blue: 0.10),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: compact ? 36 : 28) {
                    Text(state.trackTitle)
                        .font(.system(size: compact ? 76 : 82, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.55)
                        .foregroundStyle(.white)
                        .frame(maxWidth: compact ? canvasSize.width * 0.84 : canvasSize.width * 0.78)

                    Text(state.activeRoleTitle)
                        .font(.system(size: compact ? 46 : 42, weight: .medium, design: .rounded))
                        .foregroundStyle(activeColor)
                        .shadow(color: activeColor.opacity(0.8), radius: 28)
                        .scaleEffect(0.97 + 0.03 * state.transitionProgress)
                        .opacity(0.62 + 0.38 * state.transitionProgress)
                }
                .padding(compact ? 72 : 54)
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .scaleEffect(scale)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color.black)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.trackTitle)、\(state.activeRoleTitle)を再生中")
    }

    private var activeColor: Color {
        state.activeSourceIndex == 0 ? firstColor : secondColor
    }

}
