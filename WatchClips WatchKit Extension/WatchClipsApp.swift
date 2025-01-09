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
    
    // MARK: - NEW: Add SettingsStore
    @StateObject private var settingsStore: SettingsStore

    init() {
        // 1) Build the actual services
        let videosService = VideosService(client: supabase)
        let cachedVideosService = CachedVideosService(videosService: videosService)
        let sharedViewModel = SharedVideosViewModel(cachedVideosService: cachedVideosService)
        let store = SettingsStore.shared  // or SettingsStore() if you prefer a fresh instance
        
        let downloadsViewModel = DownloadsViewModel(
            cachedVideosService: cachedVideosService,
            sharedVM: sharedViewModel,
            settingsStore: store
        )

        // Create your user settings service (whatever it does in your code)
        let userSettingsService = UserSettingsService(client: supabase)
        
        // 2) Create the SettingsStore (shared or new instance)


        // 3) Wrap them all in @StateObject
        _mainVideosService       = StateObject(wrappedValue: videosService)
        _mainCachedService       = StateObject(wrappedValue: cachedVideosService)
        _mainDownloadsVM         = StateObject(wrappedValue: downloadsViewModel)
        _sharedVM                = StateObject(wrappedValue: sharedViewModel)
        
        _mainUserSettingsService = StateObject(wrappedValue: userSettingsService)
        
        // NEW: Wrap SettingsStore as well
        _settingsStore           = StateObject(wrappedValue: store)
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
                
                // NEW: Make the SettingsStore available to the entire app
                .environmentObject(settingsStore)
        }
    }
}
