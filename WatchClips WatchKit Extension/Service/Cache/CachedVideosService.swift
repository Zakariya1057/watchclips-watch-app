import Foundation

class CachedVideosService: ObservableObject {
    private let videosService: VideosService
    
    // Replace any file-related constants with a reference to our repository
    private let repository = CachedVideosRepository.shared

    init(videosService: VideosService) {
        self.videosService = videosService
    }
    
    // MARK: - Public API (Signatures Remain the Same)

    /// Loads all cached videos from the SQLite DB
    func loadCachedVideos() -> [Video]? {
        let cached = repository.loadAllVideos()
        return cached.isEmpty ? nil : cached
    }
    
    /// Tries to load videos from cache first. If none in cache or force refresh is needed, fetches from remote.
    func fetchVideos(forCode code: String, useCache: Bool = true) async throws -> [Video] {
        // 1) Try loading from repository (local DB) first
        if useCache, let cached = loadCachedVideos() {
            // Return cached immediately
            let cachedResult = cached
            
            // 2) Attempt a remote refresh in background
            Task {
                do {
                    let fresh = try await videosService.fetchVideos(forCode: code)
                    
                    // First, save or upsert the fresh videos to the cache
                    saveToCache(videos: fresh)
                    
                    // Then find which videos are missing in `fresh` but were in `cachedResult`
                    let freshIDs = Set(fresh.map { $0.id })
                    let cachedIDs = Set(cachedResult.map { $0.id })
                    let removedIDs = cachedIDs.subtracting(freshIDs)
                    
                    // Remove from our local cache + downloads store
                    for videoId in removedIDs {
                        removeFromCache(id: videoId)
                        DownloadsStore.shared.removeById(videoId: videoId)
                    }
                    
                } catch {
                    print("[CachedVideosService] Remote fetch failed. Using cached.")
                }
            }
            
            return cachedResult
        } else {
            // 3) If no valid cache or ignoring cache, fetch from the server
            let fresh = try await videosService.fetchVideos(forCode: code)
            saveToCache(videos: fresh)
            return fresh
        }
    }
    
    public func fetchVideo(forCode code: String, forVideoId videoId: String) async throws -> Video? {
        // Keep the same logic: fetch all, then find the one with the matching ID
        let videos = try await fetchVideos(forCode: code, useCache: true)
        return videos.first { $0.id == videoId }
    }

    /// Forces a refresh from remote, ignoring the cache. Throws error if offline.
    func refreshVideos(forCode code: String) async throws -> [Video] {
        let fresh = try await videosService.fetchVideos(forCode: code)
        saveToCache(videos: fresh)
        return fresh
    }
    
    /// Removes a video from the cache by its ID
    func removeFromCache(id: String) {
        // Instead of modifying an in-memory array + re-saving to JSON,
        // we just tell the repository to delete by ID:
        repository.removeVideoById(id)
    }
    
    /// Deletes all cached videos
    func clearCache() {
        repository.removeAllVideos()
        print("[CachedVideosService] Cache cleared.")
    }

    // MARK: - Internals
    
    /// Saves an array of videos to the local DB (SQLite).
    private func saveToCache(videos: [Video]) {
        repository.saveVideos(videos)
    }
}
