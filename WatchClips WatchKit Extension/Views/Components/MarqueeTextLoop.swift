//
//  MarqueeTextLoop.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 29/12/2024.
//


import SwiftUI

struct MarqueeTextLoop: View {
    let text: String
    let font: Font
    let speed: Double         // points/sec
    let initialDelay: Double  // pause before first scroll
    let pauseTime: Double     // pause after finishing one scroll
    
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offsetX: CGFloat = 0
    @State private var isScrolling = false

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(font)
                .background(
                    GeometryReader { textGeo -> Color in
                        DispatchQueue.main.async {
                            textWidth = textGeo.size.width
                            containerWidth = geo.size.width
                        }
                        return Color.clear
                    }
                )
                .offset(x: offsetX)
                .clipped()
                .onAppear {
                    // Only scroll if needed
                    if textWidth > containerWidth {
                        startLoop()
                    }
                }
        }
    }

    /// Repeatedly scroll from right->left, then jump back, with pauses.
    private func startLoop() {
        // Start fully visible (offset = 0)
        offsetX = 0
        
        // Schedule the first animation
        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) {
            scrollLeft()
        }
    }

    private func scrollLeft() {
        // Distance to travel is textWidth - containerWidth (for fully visible start -> fully hidden left)
        // But if you want the text to go completely off the left side, use `textWidth + containerWidth`
        let distance = textWidth + containerWidth
        let duration = distance / speed
        
        withAnimation(Animation.linear(duration: duration)) {
            // Move it fully off the left edge
            offsetX = -textWidth
        }

        // After finishing, wait pauseTime, then jump back to offset=containerWidth and scroll again
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + pauseTime) {
            offsetX = containerWidth
            scrollLeft()   // repeat
        }
    }
}
