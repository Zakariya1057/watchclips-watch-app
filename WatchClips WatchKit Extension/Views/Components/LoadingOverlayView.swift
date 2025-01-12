import SwiftUI

struct LoadingOverlayView: View {
    let isLongWait: Bool
    let hideSpinner: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            if !hideSpinner {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            }

            if isLongWait {
                Text("Sorry, this is taking a bit long to get your videos…")
                    .font(.headline)
            } else {
                Text("Loading videos…")
                    .font(.headline)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }
}
