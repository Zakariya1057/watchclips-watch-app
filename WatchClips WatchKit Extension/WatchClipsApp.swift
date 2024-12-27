//
// MyWatchApp.swift
// WatchClips Watch App
//
import SwiftUI

@main
struct MyWatchApp: App {
    // Create and store them as single @StateObject instances:
    @StateObject private var mainVideosService: VideosService
    @StateObject private var mainCachedService: CachedVideosService
    @StateObject private var mainDownloadsVM: DownloadsViewModel

    init() {
        // 1) Build the actual services
        let videosService = VideosService(client: supabase)
        let cachedVideosService = CachedVideosService(videosService: videosService)
        let downloadsViewModel = DownloadsViewModel(cachedVideosService: cachedVideosService)
        
        // 2) Wrap them in @StateObject:
        _mainVideosService = StateObject(wrappedValue: videosService)
        _mainCachedService = StateObject(wrappedValue: cachedVideosService)
        _mainDownloadsVM   = StateObject(wrappedValue: downloadsViewModel)
    }

    var body: some Scene {
        WindowGroup {
            // Provide them to the environment so child views see the same instance
            ContentView()
                .environmentObject(mainVideosService)
                .environmentObject(mainCachedService)
                .environmentObject(mainDownloadsVM)
        }
    }
}
