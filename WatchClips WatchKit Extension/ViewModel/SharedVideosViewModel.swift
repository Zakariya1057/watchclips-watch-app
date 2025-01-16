//
//  SharedVideosViewModel.swift
//  WatchClips
//

import Foundation
import SwiftUI

@MainActor
class SharedVideosViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isOffline = false
    @Published var isInitialLoad = true
    
    @AppStorage("loggedInState") public var loggedInStateData = Data()
    
    private let cachedVideosService: CachedVideosService
    
    // Updated cached user settings service
    private lazy var cachedUserSettingsService = CachedUserSettingsService(
        userSettingsService: userSettingsService,
        codeService: codeService
    )
    
    // Remote user settings service (for Supabase or similar)
    private let userSettingsService = UserSettingsService(client: supabase)
    private let codeService = CodeService(client: supabase)
    
    /// Optional: Store your "activePlan"
    @Published var activePlan: Plan?
    
    /// userId is optional; can be `nil` if logged out or missing
    private var userId: UUID? {
        return decodeLoggedInState(from: loggedInStateData)?.userId
    }
    
    private var code: String? {
        return decodeLoggedInState(from: loggedInStateData)?.code
    }
    
    var loggedInState: LoggedInState? {
        return decodeLoggedInState(from: loggedInStateData)
    }
    
    /// Pass in your existing services + user code
    init(cachedVideosService: CachedVideosService) {
        self.cachedVideosService = cachedVideosService
        
        Task {
            let code = decodeLoggedInState(from: loggedInStateData)?.code ?? ""
            self.videos = try await cachedVideosService.fetchVideos(forCode: code)
            
            // Attempt to fetch the plan (will skip remote if userId == nil)
            await fetchPlan()
        }
    }
    
    func setVideos(cachedVideos: [Video]) {
        videos = cachedVideos
    }
    
    // MARK: - Load (initial)
    func loadVideos(code: String, useCache: Bool = true) async {
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            let oldVideos = try await cachedVideosService.fetchVideos(forCode: code, useCache: true)
            let fetchedVideos = try await cachedVideosService.fetchVideos(forCode: code, useCache: useCache)
            self.videos = fetchedVideos
            onDeletedVideo(newVideos: fetchedVideos, oldVideos: oldVideos)
            
            if isOffline, !useCache {
                self.isOffline = false
            }
            self.isInitialLoad = false
        } catch {
            // Attempt to use local cached videos
            let cached = cachedVideosService.loadCachedVideos()
            if let cached = cached, !cached.isEmpty {
                self.videos = cached
                self.isOffline = true
                self.errorMessage = error.localizedDescription
            } else {
                self.videos = []
                self.isOffline = true
                self.errorMessage = error.localizedDescription
            }
            self.isInitialLoad = false
        }
        
        Task {
            await fetchPlan(useCache: false)
        }
    }
    
    func onDeletedVideo(newVideos: [Video], oldVideos: [Video]) {
        // figure out which videos are "missing" after refresh
        let fetchedIDs = Set(newVideos.map(\.id))
        let missingVideos = oldVideos.filter { !fetchedIDs.contains($0.id) }
        
        // Clean up missing videos from disk if you want
        for missingVid in missingVideos {
            print("Deleting video: \(missingVid.title ?? "")")
            DownloadsStore.shared.removeById(videoId: missingVid.id)
            SegmentedDownloadManager.shared.removeDownloadCompletely(
                videoId: missingVid.id,
                fileExtension: (missingVid.filename as NSString).pathExtension
            )
            PlaybackProgressService.shared.clearProgress(videoId: missingVid.id)
        }
    }
    
    // MARK: - Refresh
    func refreshVideos(code: String, forceRefresh: Bool = true) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let oldVideos = try await cachedVideosService.fetchVideos(forCode: code, useCache: true)
            
            let fetchedVideos = try await (
                forceRefresh
                ? cachedVideosService.refreshVideos(forCode: code)
                : oldVideos
            )
            
            
            if isOffline, forceRefresh {
                self.isOffline = false
            }
            
            print(fetchedVideos.map {$0.id} )
            
            self.videos = fetchedVideos
            self.isInitialLoad = false
            self.errorMessage = nil
            onDeletedVideo(newVideos: fetchedVideos, oldVideos: oldVideos)
        } catch {
            let cached = cachedVideosService.loadCachedVideos()
            if let cached = cached, !cached.isEmpty {
                self.videos = cached
                self.isOffline = true
                self.errorMessage = error.localizedDescription
            } else {
                self.videos = []
                self.isOffline = true
                self.errorMessage = error.localizedDescription
            }
            self.isInitialLoad = false
        }
        
        Task {
            await fetchPlan(useCache: false)
        }
    }
    
    // MARK: - Plan fetching (optional)
    /// Example method to fetch the user plan from your new `CachedUserSettingsService`
    /// - If `userId` is nil, remote fetch is skipped; local plan is returned if `useCache == true`.
    func fetchPlan(useCache: Bool = true) async {
        do {
            // 1) If we're NOT using the cache (meaning we want fresh data) AND we have no userId yet,
            //    try to fetch one via the 'code' property.
            if !useCache, userId == nil, let code = code {
                if let newUserId = await cachedUserSettingsService.fetchUserId(id: code) {
                    print("[SharedVideosViewModel] New user_id created: \(newUserId)")

                    // Update our loggedInState with the newly fetched userId
                    if var state = loggedInState {
                        state.userId = newUserId
                        if let encodedState = encodeLoggedInState(state) {
                            loggedInStateData = encodedState
                        }
                    }
                }
            }
            
            // 2) Attempt to fetch the active plan (the `CachedUserSettingsService`
            //    can decide if it goes remote or local if `userId` is nil).
            let plan = try await cachedUserSettingsService.fetchActivePlan(
                forUserId: userId,
                useCache: useCache
            )
            
            // 3) Update our local state’s plan and re-store in `loggedInStateData`
            if var updatedState = loggedInState {
                updatedState.activePlan = plan
                if let encodedLoggedInState = encodeLoggedInState(updatedState) {
                    loggedInStateData = encodedLoggedInState
                }
            }
            
            // Also store plan in the @Published `activePlan`
            self.activePlan = plan
            
        } catch {
            print("[SharedVideosViewModel] fetchPlan failed: \(error)")
        }
    }
    
    // MARK: - Delete all (for logout)
    func deleteAllVideosAndLogout() async {
        print("Deleting all and logging out")
        isLoading = true
        defer { isLoading = false }
        
        UserDefaults.standard.removeObject(forKey: "loggedInState")
        loggedInStateData = Data()
        
        // Clear local arrays
        self.videos = []
        
        // Clear local plan
        self.activePlan = nil
        
        // Clear all downloads, caches, etc.
        Task.detached {
            await self.cachedVideosService.clearCache()
            DownloadsStore.shared.clearAllDownloads()
            SegmentedDownloadManager.shared.deleteAllSavedVideos()
            SegmentedDownloadManager.shared.wipeAllDownloadsCompletely()
            PlaybackProgressService.shared.clearAllProgress()
            
            // Remove any stored single plan from local repository
           await self.cachedUserSettingsService.removeFromCache()
        }
    }
}
