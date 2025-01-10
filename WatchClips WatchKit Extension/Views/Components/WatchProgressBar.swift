//
//  WatchProgressBar.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 10/01/2025.
//

import SwiftUI

struct WatchProgressBar: View {
    let watchProgress: Double      // e.g. 35 (seconds)
    let totalDuration: Double      // e.g. 120 (seconds)
    
    var body: some View {
        GeometryReader { geo in
            // Calculate fraction
            let fraction = totalDuration > 0 ? (watchProgress / totalDuration) : 0
            let clampedFraction = max(0, min(1, fraction))
            
            ZStack(alignment: .leading) {
                // Background bar (full width, 4 pt high)
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: geo.size.width, height: 4)
                
                // Filled portion with darker green + rounded corners
                Rectangle()
                    .fill(Color(red: 1.0, green: 0.0, blue: 0.0))  // a "dark green"
                    .frame(width: geo.size.width * CGFloat(clampedFraction), height: 4)
                    .cornerRadius(2)  // apply rounding to corners
            }
            .frame(height: 4)
        }
        // Constrain the geometry’s total height to 4 points
        .frame(height: 4)
    }
}
