import SwiftUI

struct ContentView: View {
    @AppStorage("loggedInCode") private var loggedInCode: String = ""
    @StateObject private var appState = AppState.shared

    // Pull from environment (same singletons from MyWatchApp)
    @EnvironmentObject var videosService: VideosService
    @EnvironmentObject var cachedService: CachedVideosService
    @EnvironmentObject var downloadViewModel: DownloadsViewModel

    var body: some View {
        NavigationStack {
            if loggedInCode.isEmpty {
                LoginView()
            } else {
                VideoListView(code: loggedInCode)
            }
        }
        .onAppear {
            downloadViewModel.loadLocalDownloads()
            downloadViewModel.resumeInProgressDownloads()
        }
        .fullScreenCover(item: $appState.selectedVideo) { video in
            VideoPlayerView(code: video.code, videoId: video.id)
                .ignoresSafeArea()
        }
    }
}
