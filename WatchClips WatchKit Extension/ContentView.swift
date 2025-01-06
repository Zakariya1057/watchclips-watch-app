import SwiftUI

struct ContentView: View {
    @AppStorage("loggedInState") private var loggedInStateData = Data()
    @StateObject private var appState = AppState.shared

    private var code: String? {
        return decodeLoggedInState(from: loggedInStateData)?.code
    }
    
    // Pull from environment (same singletons from MyWatchApp)
    @EnvironmentObject var videosService: VideosService
    @EnvironmentObject var cachedService: CachedVideosService
    @EnvironmentObject var downloadViewModel: DownloadsViewModel

    var body: some View {
        NavigationStack {
            if loggedInStateData.isEmpty {
                LoginView()
            } else {
                VideoListView()
            }
        }
        .onAppear {
            downloadViewModel.loadLocalDownloads()
            downloadViewModel.resumeInProgressDownloads()
        }
        .fullScreenCover(item: $appState.selectedVideo) { video in
            VideoPlayerView(code: video.code, videoId: video.id, filename: video.filename)
                .ignoresSafeArea()
        }
    }
}
