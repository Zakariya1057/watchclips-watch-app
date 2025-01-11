import SwiftUI

struct LoadingView: View {
    var body: some View {
        HStack {
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)

                Text("Loading videos...")
                    .font(.headline)

                Text("It's taking a bit of time.\nPlease be patient.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .padding()
    }
}

struct LoadingView_Previews: PreviewProvider {
    static var previews: some View {
        LoadingView()
    }
}
