import SwiftUI
import WatchKit

// MARK: - SettingsView
struct SettingsView: View {
    @State private var notifyOnDownload = true
    @State private var notifyOnOptimize = false
    
    @State private var showLogoutConfirmation = false
    @EnvironmentObject private var sharedVM: SharedVideosViewModel
    
    @EnvironmentObject private var settingsStore: SettingsStore
    
    var body: some View {
        List {
            // Notifications Section
            Section("Notifications") {
                Toggle("Notify on Video Downloaded",
                       isOn: Binding(
                           get: { settingsStore.settings.notifyOnDownload },
                           set: { newVal in
                               settingsStore.setNotifyOnDownload(newVal)
                           }
                       ))
                
                Toggle("Notify on Video Optimized",
                       isOn: Binding(
                           get: { settingsStore.settings.notifyOnOptimize },
                           set: { newVal in
                               settingsStore.setNotifyOnOptimize(newVal)
                           }
                       ))
            }
            
            // Support Section
            Section("Support") {
                NavigationLink("Help", destination: HelpSupportView())
                NavigationLink("Feedback", destination: FeedbackView())
            }
            
            // Log Out Section
            Section {
                Button(role: .destructive) {
                    showLogoutConfirmation = true
                } label: {
                    Text("Log Out")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Confirm Logout",
               isPresented: $showLogoutConfirmation,
               actions: {
            Button("Cancel", role: .cancel) {}
            Button("Logout", role: .destructive) {
                Task {
                    await deleteAllVideosAndLogout()
                }
            }
        }, message: {
            Text("This will also delete all downloaded videos. Are you sure?")
        })
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func deleteAllVideosAndLogout() async {
        await sharedVM.deleteAllVideosAndLogout()
    }
}

// MARK: - HelpSupportView
struct HelpSupportView: View {
    var body: some View {
        List {
            Section("Need assistance?") {
                Text("We’re here to help!")
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 4)
            }
            
            Section("Contact") {
                Text("""
Please email us at:
support@watchclips.app

We’ll be happy to assist you!
""")
                .padding(.vertical, 10)
            }
        }
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - FeedbackView
struct FeedbackView: View {
    var body: some View {
        List {
            Section("We’d love to hear your thoughts!") {
                Text("""
You can reach us at 
support@watchclips.app.
""")
                .padding(.vertical, 10)
            }
        }
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.inline)
    }
}
