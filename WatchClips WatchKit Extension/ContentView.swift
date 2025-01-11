import SwiftUI

struct ContentView: View {
    @AppStorage("loggedInState") private var loggedInStateData = Data()
    @StateObject private var appState = AppState.shared
    
    @EnvironmentObject var videosService: VideosService
    @EnvironmentObject var cachedService: CachedVideosService
    @EnvironmentObject var downloadViewModel: DownloadsViewModel
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
                                    downloadViewModel.setVideos(newVideos: sharedVM.videos)
                                    downloadViewModel.resumeInProgressDownloads()
                                    downloadViewModel.onAppearCheckForURLChanges()
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
            // Optional: You can switch between .automatic, .never, or remove this
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
            // Full-screen video player if a video is selected
            .fullScreenCover(item: $appState.selectedVideo) { video in
                VideoPlayerView(
                    code: video.code,
                    videoId: video.id,
                    filename: video.filename
                )
                .ignoresSafeArea()
            }
        }
    }
}
