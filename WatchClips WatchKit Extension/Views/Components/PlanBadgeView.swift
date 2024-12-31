//
//  PlanBadgeView.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//

import SwiftUI

struct PlanBadgeView: View {
    let planName: PlanName
    
    var isPro: Bool {
        planName == .pro
    }

    var body: some View {
        ZStack {
            if isPro {
                // PRO Gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.blue,
                        Color.purple,
                        Color.pink
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .cornerRadius(12)
                .opacity(0.4)       // Semi-transparent
                .frame(height: 28)
            } else {
                // FREE => Basic background
                Rectangle()
                    .fill(Color.gray.opacity(0.2)) // A subtle gray background
                    .cornerRadius(12)
                    .frame(height: 28)
            }

            // Foreground text label
            Text(planName.displayName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .padding(.vertical, 3)
        }
        .frame(minWidth: 50)
    }
}
