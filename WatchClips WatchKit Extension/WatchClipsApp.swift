
import SwiftUI

@main
struct MyWatchApp: App {
    // Existing service objects
    @StateObject private var mainVideosService: VideosService
    @StateObject private var mainCachedService: CachedVideosService
    @StateObject private var mainDownloadsVM: DownloadsViewModel
    @StateObject private var sharedVM: SharedVideosViewModel
    
    // NEW: Add a UserSettingsService
    @StateObject private var mainUserSettingsService: UserSettingsService

    init() {
        // 1) Build the actual services
        let videosService = VideosService(client: supabase)
        let cachedVideosService = CachedVideosService(videosService: videosService)
        let downloadsViewModel = DownloadsViewModel(cachedVideosService: cachedVideosService)
        let sharedViewModel = SharedVideosViewModel(cachedVideosService: cachedVideosService)
        
        // NEW: Create your user settings service
        let userSettingsService = UserSettingsService(client: supabase)
        
        // 2) Wrap them all in @StateObject
        _mainVideosService       = StateObject(wrappedValue: videosService)
        _mainCachedService       = StateObject(wrappedValue: cachedVideosService)
        _mainDownloadsVM         = StateObject(wrappedValue: downloadsViewModel)
        _mainUserSettingsService = StateObject(wrappedValue: userSettingsService)
        _sharedVM                = StateObject(wrappedValue: sharedViewModel)
    }
    
    var body: some Scene {
        WindowGroup {
            // Provide them to the environment so child views see the same instances
            ContentView()
                .environmentObject(mainVideosService)
                .environmentObject(mainCachedService)
                .environmentObject(mainDownloadsVM)
                .environmentObject(mainUserSettingsService)
                .environmentObject(sharedVM)
                .environmentObject(PlaybackProgressService.shared)
        }
    }
}
