//
//  MinimalLargeButtonStyle.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 27/12/2024.
//

import WatchKit
import SwiftUI

/// A minimal large button style (no background, full width).
struct MinimalLargeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
            .contentShape(Rectangle()) // ensures entire row is tappable
            .foregroundColor(configuration.isPressed ? .primary.opacity(0.7) : .primary)
    }
}
