//
//  ContentView.swift
//  WatchClips
//

import SwiftUI

struct ContentView: View {
    @AppStorage("loggedInState") private var loggedInStateData = Data()
    @StateObject private var appState = AppState.shared
    
    // Pull from environment or create on the fly
    @EnvironmentObject var videosService: VideosService
    @EnvironmentObject var cachedService: CachedVideosService
    @EnvironmentObject var downloadViewModel: DownloadsViewModel
    
    // IMPORTANT: Also inject the new SharedVideosViewModel
    // (Alternatively, you can create it in your @main App if you prefer.)
    @EnvironmentObject private var sharedVM: SharedVideosViewModel
    
    init() {
        // Example of reading the code from loggedInState
        let code = decodeLoggedInState(from: _loggedInStateData.wrappedValue)?.code ?? ""
        
        // Create the SharedVideosViewModel with your existing cachedService
        let cached = CachedVideosService(videosService: VideosService(client: supabase))
    }
    
    var body: some View {
        NavigationStack {
            if loggedInStateData.isEmpty {
                LoginView()
            } else {
                // Provide the environment object to children
                VideoListView()
            }
        }
        .onAppear {
            // If you want to load local partial downloads
            downloadViewModel.loadLocalDownloads()
            downloadViewModel.resumeInProgressDownloads()
        }
        // Also, if you want the full screen video player
        .fullScreenCover(item: $appState.selectedVideo) { video in
            VideoPlayerView(code: video.code, videoId: video.id, filename: video.filename)
                .ignoresSafeArea()
        }
    }
}
