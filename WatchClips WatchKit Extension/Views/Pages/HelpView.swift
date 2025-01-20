import SwiftUI

// MARK: - Main HelpView
struct HelpView: View {
    var body: some View {
        NavigationView {
            List {
                // Existing items
                NavigationLink("What does 'Optimizing' / 'Optimized' mean?", destination: WhatIsOptimizingView())
                NavigationLink("Why did my download restart?", destination: WhyDidMyDownloadRestartView())
                NavigationLink("How to Change Volume", destination: HowToChangeVolumeView())
                NavigationLink("How to Skip Ahead", destination: HowToSkipAheadView())
                NavigationLink("How to Connect Headphones/AirPods", destination: HowToConnectHeadphonesView())
                NavigationLink("How to Keep App from Exiting", destination: HowToKeepAppOpenView())
                
                // NEW: Video/Audio Keeps Stopping section
                NavigationLink("Video/Audio Keeps Stopping?", destination: PlaybackStopsView())
            }
            .padding(.top, 20)
        }
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Video/Audio Keeps Stopping?
struct PlaybackStopsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Video/Audio Keeps Stopping?")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("""
If your video or audio stops when you press play, it could be because:
• Your watch is currently on the charger
• Low Power Mode is enabled

Try removing your watch from the charger or disabling Low Power Mode, and see if playback resumes normally. These power-saving features can sometimes pause background apps or media playback.

Steps to disable Low Power Mode:
1. On your Apple Watch, open Settings.
2. Tap on Battery.
3. Toggle off Low Power Mode (if it’s on).

Once done, re-open WatchClips and play your video/audio again.
""")
                .font(.body)
                .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("Playback Stopping?")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Why Did My Download Restart?
struct WhyDidMyDownloadRestartView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                Text("Why Did My Download Restart?")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("""
Occasionally, while downloading, we detect that the file can be further optimized for your Apple Watch. When this happens, we switch to the newer, optimized version. While this may cause your download to restart from the beginning, it often results in:

- Smaller final file size
- Faster overall download
- Less storage used on your Apple Watch

We always measure how much you've already downloaded versus how much time is saved by switching. In most cases, starting the download over with the optimized file gets you watching sooner. Rest assured, it’s all about reducing wait times and saving space on your Watch.
""")
                .font(.body)
                .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("Download Restart")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - WhatIsOptimizingView
struct WhatIsOptimizingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                Text("What does 'Optimizing' / 'Optimized' mean?")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("""
When you upload a video, we automatically optimize it in the background to reduce file size without sacrificing quality on your Apple Watch. This makes:
- Downloads faster over Wi-Fi or cellular.
- Less storage used on your Watch for larger videos.

**Can I still download before it's done?**  
Yes! You can choose to download immediately. However, if the file is large (e.g., over 1GB), we suggest waiting until optimization completes to get a noticeably smaller file.
""")
                .font(.body)
                .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("'Optimizing' Explained")
    }
}

// MARK: - HowToKeepAppOpenView
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

// MARK: - HowToConnectHeadphonesView
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
   - Tap the AirPlay icon to see available audio outputs.
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

// MARK: - HowToChangeVolumeView
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

// MARK: - HowToSkipAheadView
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

// MARK: - Preview
struct HelpView_Previews: PreviewProvider {
    static var previews: some View {
        HelpView()
    }
}
