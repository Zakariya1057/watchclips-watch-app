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
    
    /// Optional: Store your "activePlan" if you also want to fetch that once
    @Published var activePlan: Plan?
    
    /// Pass in your existing services + user code
    init(cachedVideosService: CachedVideosService) {
        self.cachedVideosService = cachedVideosService
        
        Task {
            let code = decodeLoggedInState(from: loggedInStateData)?.code ?? ""
            self.videos = try await cachedVideosService.fetchVideos(forCode: code)
        }
    }
    
    // MARK: - Load (initial) 
    func loadVideos(code: String, useCache: Bool = true) async {
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            let fetchedVideos = try await cachedVideosService.fetchVideos(forCode: code, useCache: useCache)
            self.videos = fetchedVideos
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
    }
    
    // MARK: - Refresh 
    func refreshVideos(code: String, forceRefresh: Bool = true) async {
        isLoading = true
        errorMessage = nil
        
        let oldVideos = self.videos
        defer { isLoading = false }
        
        do {
            let fetchedVideos = try await (
                forceRefresh
                ? cachedVideosService.refreshVideos(forCode: code)
                : cachedVideosService.fetchVideos(forCode: code, useCache: true)
            )
            
            // figure out which videos are "missing" after refresh
            let fetchedIDs = Set(fetchedVideos.map(\.id))
            let missingVideos = oldVideos.filter { !fetchedIDs.contains($0.id) }
            
            self.videos = fetchedVideos
            self.isOffline = false
            self.isInitialLoad = false
            self.errorMessage = nil
            
            // Clean up missing videos from disk if you want
            for missingVid in missingVideos {
                VideoDownloadManager.shared.deleteVideoFor(code: missingVid.code, videoId: missingVid.id)
            }
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
    }
    
    // MARK: - Plan fetching (optional)
    /// Example method to fetch the user plan from your existing service
    func fetchPlan(userSettingsService: UserSettingsService, userId: UUID) async {
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
        isLoading = true
        defer { isLoading = false }
        
        // Clear the entire loggedInState
        loggedInStateData = Data()
        
        // Clear local arrays
        self.videos = []
        
        // Clear all downloads, caches, etc.
        Task.detached {
            await downloadStore.clearAllDownloads()
            await self.cachedVideosService.clearCache()
            PlaybackProgressService.shared.clearAllProgress()
            VideoDownloadManager.shared.deleteAllSavedVideos()
        }
    }
}
