import SwiftUI

// MARK: - Main HelpView
struct HelpView: View {
    var body: some View {
        NavigationView {
            List {
                NavigationLink("How to Change Volume", destination: HowToChangeVolumeView())
                NavigationLink("How to Skip Ahead", destination: HowToSkipAheadView())
                
                // How to Connect Headphones/AirPods
                NavigationLink("How to Connect Headphones/AirPods",
                               destination: HowToConnectHeadphonesView())
                
                // NEW: How to Keep App from Exiting
                NavigationLink("How to Keep App from Exiting",
                               destination: HowToKeepAppOpenView())
                
                NavigationLink("How to Log Out", destination: HowToLogoutView())
            }
            .padding(.top, 20)
        }
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - How to Keep App from Exiting
struct HowToKeepAppOpenView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                Text("How to Keep App from Exiting")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("""
By default, your Apple Watch may return to the watch face after a short period of inactivity. To keep “WatchClips” open longer, follow these steps on your iPhone:
""")
                .font(.body)
                
                Group {
                    Text("1. Open the **Watch** app on your iPhone.")
                    Text("2. Tap on **General**.")
                    Text("3. Scroll down and choose **Return to Clock**.")
                    Text("4. Under the list of apps, find **WatchClips** and switch **Return to App** to ON (or Enabled).")
                    Text("5. Set **Return to Clock** to **After 1 hour** (the maximum) so the app remains active.")
                }
                .font(.body)
                .padding(.leading, 4)
                
                Text("""
With these settings, the Watch will stay in the WatchClips app for up to an hour before automatically returning to the watch face.
""")
                .font(.body)
            }
            .padding()
        }
        .navigationTitle("Keep App from Exiting")
    }
}

// MARK: - How to Connect Headphones/AirPods
struct HowToConnectHeadphonesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                Text("How to Connect Headphones/AirPods")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("""
1. Press the side button on your Apple Watch to open Control Center.
   - Scroll down if needed.
   - Tap the AirPlay icon (sometimes shown as an AirPlay or AirDrop icon) to see available audio outputs.
""")
                .font(.body)
                
                Image("airpods1")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .background(Color.white)
                    .cornerRadius(8)
                
                Text("""
2. Select your AirPods or headphones from the list.
   - Once connected, audio from videos or other apps on your Apple Watch will play through them.
""")
                .font(.body)
                
                Image("airpods2")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .background(Color.white)
                    .cornerRadius(8)
                
            }
            .padding()
        }
        .navigationTitle("Connect Headphones")
    }
}

// MARK: - Existing Detail Views
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
3. Clockwise increases volume; counterclockwise decreases it.
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
