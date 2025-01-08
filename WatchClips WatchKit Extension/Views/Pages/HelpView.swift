import SwiftUI

// MARK: - Main HelpView
struct HelpView: View {
    var body: some View {
        NavigationView {
            List {
                NavigationLink("How to Change Volume", destination: HowToChangeVolumeView())
                NavigationLink("How to Skip Ahead", destination: HowToSkipAheadView())
                NavigationLink("How to Log Out", destination: HowToLogoutView())
            }
            .padding(.top, 20)
        }
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Detail Views
struct HowToChangeVolumeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("How to Change Volume")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("""
1. Pick any video to watch.
2. Turn the Digital Crown to raise or lower the volume.
3. Clockwise increases volume, counterclockwise decreases it.
""")
                .font(.body)
            }
            .padding()
        }
        .navigationTitle("Change Volume")
    }
}

struct HowToSkipAheadView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("How to Skip Ahead")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("""
1. Pick a video.
2. Tap the progress bar at the bottom.
3. Turn the Digital Crown to jump forward or back.
""")
                .font(.body)
            }
            .padding()
        }
        .navigationTitle("Skip Ahead")
    }
}

struct HowToLogoutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("How to Log Out")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("""
1. On the Home screen, scroll down.
2. Tap “Log Out” to end your session.
3. You’ll return to the login screen.
""")
                .font(.body)
            }
            .padding()
        }
        .navigationTitle("Log Out")
    }
}

// MARK: - Preview
struct HelpView_Previews: PreviewProvider {
    static var previews: some View {
        HelpView()
    }
}
