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
    
    @AppStorage("loggedInState") private var loggedInStateData = Data()
    
    private let cachedVideosService: CachedVideosService
    
    private let userSettingsService = UserSettingsService(client: supabase)
    
    /// Optional: Store your "activePlan" if you also want to fetch that once
    @Published var activePlan: Plan?
    
    private var userId: UUID? {
        return decodeLoggedInState(from: loggedInStateData)?.userId
    }
    
    /// Pass in your existing services + user code
    init(cachedVideosService: CachedVideosService) {
        self.cachedVideosService = cachedVideosService
        
        Task {
            let code = decodeLoggedInState(from: loggedInStateData)?.code ?? ""
            self.videos = try await cachedVideosService.fetchVideos(forCode: code)
            
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
            self.isOffline = false
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
            await fetchPlan()
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
            SegmentedDownloadManager.shared.removeDownloadCompletely(videoId: missingVid.id)
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
            
            self.videos = fetchedVideos
            self.isOffline = false
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
            await fetchPlan()
        }
    }
    
    // MARK: - Plan fetching (optional)
    /// Example method to fetch the user plan from your existing service
    func fetchPlan() async {
        do {
            let freshPlan = try await userSettingsService.fetchActivePlan(forUserId: userId)
            self.activePlan = freshPlan
        } catch {
            print("[SharedVideosViewModel] fetchPlan failed: \(error)")
        }
    }
    
    // MARK: - Delete all (for logout)
    func deleteAllVideosAndLogout(
        downloadStore: DownloadsStore
    ) async {
        print("Deleting all and logging out")
        isLoading = true
        defer { isLoading = false }
        
        UserDefaults.standard.removeObject(forKey: "loggedInState")
        
        // Clear local arrays
        self.videos = []
        
        activePlan = nil
        
        // Clear all downloads, caches, etc.
        Task.detached {
            await self.cachedVideosService.clearCache()
            downloadStore.clearAllDownloads()
            SegmentedDownloadManager.shared.deleteAllSavedVideos()
            SegmentedDownloadManager.shared.wipeAllDownloadsCompletely()
            PlaybackProgressService.shared.clearAllProgress()
            UserSettingsRepository.shared.removeAll()
            SegmentedDownloadManager.shared.deleteAllSavedVideos()
        }
    }
}
