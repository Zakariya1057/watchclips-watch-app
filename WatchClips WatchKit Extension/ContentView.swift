import SwiftUI

struct ContentView: View {
    @AppStorage("loggedInState") private var loggedInStateData = Data()
    @StateObject private var appState = AppState.shared
    
    @EnvironmentObject var videosService: VideosService
    @EnvironmentObject var cachedService: CachedVideosService
    @EnvironmentObject var downloadViewModel: DownloadsViewModel
    @EnvironmentObject private var sharedVM: SharedVideosViewModel
    
    private var code: String? {
        decodeLoggedInState(from: loggedInStateData)?.code
    }
    
    @State private var videosSet: Bool = false
    
    var body: some View {
        
        if loggedInStateData.isEmpty {
            NavigationStack {
                LoginView()
            }
        } else {
            // Main content is now split between two tabs
            TabView {
                // VideoList tab
                NavigationStack {
                    VideoListView()
                        .onAppear {
                            Task {
                                if let code = code {
                                    await sharedVM.loadVideos(code: code, useCache: videosSet)
                                    downloadViewModel.setVideos(newVideos: sharedVM.videos)
                                    downloadViewModel.resumeInProgressDownloads()
                                    self.videosSet = true
                                }
                            }
                        }
                }
                
                // Help tab
                NavigationStack {
                    HelpView()
                }
            }
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
