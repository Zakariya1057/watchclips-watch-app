import SwiftUI

// MARK: - Main HelpView
struct HelpView: View {
    var body: some View {
        NavigationView {
            List {
                NavigationLink("How to Change Volume", destination: HowToChangeVolumeView())
                NavigationLink("How to Scrub Ahead", destination: HowToScrubAheadView())
                NavigationLink("How to Logout", destination: HowToLogoutView())
            }.padding(.top, 20)
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
                Text("How to Change the Volume")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("""
1. Choose your video.
2. Use the Digital Crown to increase or decrease the volume.
3. Turn clockwise to raise volume, counterclockwise to lower.
""")
                .font(.body)
            }
            .padding()
        }
        .navigationTitle("Change Volume")
    }
}

struct HowToScrubAheadView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("How to Scrub Ahead")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("""
1. Choose your video.
2. The progress bar is at the bottom of the screen.
3. Tap it, then turn the Digital Crown to move forward or backward.
""")
                .font(.body)
            }
            .padding()
        }
        .navigationTitle("Scrub Ahead")
    }
}

struct HowToLogoutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("How to Logout")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("""
1. From the Home, scroll down.
2. Tap “Log out” to end your session.
3. You’ll return to the login screen.
""")
                .font(.body)
            }
            .padding()
        }
        .navigationTitle("Logout")
    }
}

// MARK: - Preview
struct HelpView_Previews: PreviewProvider {
    static var previews: some View {
        HelpView()
    }
}
