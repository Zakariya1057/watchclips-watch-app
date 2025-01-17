import SwiftUI

struct ContentView: View {
    @AppStorage("loggedInState") private var loggedInStateData = Data()
    @StateObject private var appState = AppState.shared
    
    @EnvironmentObject var videosService: VideosService
    @EnvironmentObject var cachedService: CachedVideosService
    @EnvironmentObject var downloadsVM: DownloadsViewModel
    @EnvironmentObject var sharedVM: SharedVideosViewModel
    
    private var code: String? {
        decodeLoggedInState(from: loggedInStateData)?.code
    }
    
    @State private var videosSet: Bool = false
    
    var body: some View {
        
        if loggedInStateData.isEmpty {
            // Not logged in => show LoginView
            NavigationStack {
                LoginView()
            }
        } else {
            // Main content split across three tabs
            TabView {
                
                // 1) Videos Tab
                NavigationStack {
                    VideoListView()
                        .onAppear {
                            Task {
                                if let code = code, (!self.videosSet || sharedVM.videos.isEmpty) {
                                    await sharedVM.loadVideos(code: code, useCache: videosSet)
                                    downloadsVM.setVideos(newVideos: sharedVM.videos)
                                    downloadsVM.resumeInProgressDownloads()
                                    self.videosSet = true
                                }
                            }
                        }
                }
                
                // 2) Help Tab
                NavigationStack {
                    HelpView()
                }
                
                // 3) Settings Tab
                NavigationStack {
                    SettingsView()
                }
            }
            .onChange(of: sharedVM.videos) { newVidoes in
                downloadsVM.setVideos(newVideos: newVidoes)
            }
            // Optional: You can switch between .automatic, .never, or remove this
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
            // Full-screen video player if a video is selected
            .fullScreenCover(item: $appState.selectedVideo) { video in
                if let video = appState.selectedVideo {
                    VideoPlayerView(video: video)
                        .ignoresSafeArea()
                }
            }
        }
    }
}
