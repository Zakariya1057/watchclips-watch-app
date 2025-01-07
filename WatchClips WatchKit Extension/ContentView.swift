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
    
    var body: some View {
        // Main content is now split between two tabs
        TabView {
            // VideoList tab
            NavigationStack {
                VideoListView()
                    .onAppear {
                        Task {
                            if let code = code {
                                let cachedVideos = (try? await cachedService.fetchVideos(forCode: code)) ?? []
                                sharedVM.setVideos(cachedVideos: cachedVideos)
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
        .onAppear {
            Task {
                downloadViewModel.loadLocalDownloads()
                downloadViewModel.resumeInProgressDownloads()
            }
        }
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
