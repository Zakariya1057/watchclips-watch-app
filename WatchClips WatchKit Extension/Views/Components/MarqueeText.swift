import SwiftUI

struct MarqueeText: View {
    let text: String
    let font: Font
    let speed: Double     // Pixels per second
    let delay: Double     // Delay (seconds) before scrolling begins

    @State private var containerWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var offsetX: CGFloat = 0
    @State private var shouldAnimate = false

    var body: some View {
        GeometryReader { containerGeo in
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize() // Enforce natural width; no wrapping
                .background(
                    GeometryReader { textGeo in
                        Color.clear
                            .onAppear {
                                textWidth = textGeo.size.width
                                containerWidth = containerGeo.size.width

                                // Only start the marquee if text actually overflows
                                if textWidth > containerWidth {
                                    shouldAnimate = true
                                }
                            }
                    }
                )
                .offset(x: offsetX)
                .onAppear {
                    // Animate only if needed
                    guard textWidth > containerWidth else { return }

                    // Wait for 'delay' seconds before we begin
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        let totalDistance = containerWidth + textWidth
                        let totalDuration = totalDistance / speed

                        // Start the animation from the "rest" position at x=0
                        offsetX = 0

                        // Then animate left to -textWidth
                        // so it fully scrolls off the screen
                        withAnimation(
                            Animation
                                .linear(duration: totalDuration)
                                .repeatForever(autoreverses: false)
                        ) {
                            offsetX = -textWidth
                        }
                    }
                }
        }
        .frame(height: fontLineHeight()) // Keep a consistent line height
    }

    // MARK: - Font Height

    /// Helper to keep a consistent height matching the chosen font
    private func fontLineHeight() -> CGFloat {
        switch font {
        case .largeTitle: return 40  // Was 34
        case .title:      return 34  // Was 28
        case .title2:     return 26  // Was 22
        case .title3:     return 24  // Was 20
        case .headline:   return 20  // Was 17
        case .subheadline:return 18  // Was 15
        case .callout:    return 19  // Was 16
        case .footnote:   return 15  // Was 13
        case .caption:    return 14  // Was 12
        default:          return 20  // Was 17
        }
    }
}
