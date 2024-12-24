import Foundation

struct CachedVideosService {
    private let videosService: VideosService
    private let cacheFileName: String = "cached_videos.json"
    
    init(videosService: VideosService) {
        self.videosService = videosService
    }

    func loadCachedVideos() -> [Video]? {
        return loadFromCache()
    }
    
    /// Tries to load videos from cache first. If none in cache or force refresh is needed, fetches from remote.
    func fetchVideos(forCode code: String, useCache: Bool = true) async throws -> [Video] {
        // 1) Try loading from local cache first
        if useCache, let cached = loadCachedVideos(), !cached.isEmpty {
            // Return cached immediately
            let cachedResult = cached

            // 2) Attempt a remote refresh in the background
            Task {
                do {
                    let fresh = try await videosService.fetchVideos(forCode: code)
                    saveToCache(videos: fresh)
                } catch {
                    // If remote fetch fails, we stay with the cached data
                    print("[CachedVideosService] Remote fetch failed. Using cached.")
                }
            }
            
            return cachedResult
        } else {
            // 3) If no valid cache, fetch from the server directly
            let fresh = try await videosService.fetchVideos(forCode: code)
            saveToCache(videos: fresh)
            return fresh
        }
    }

    /// Forces a refresh from remote, ignoring the cache. Throws error if offline.
    func refreshVideos(forCode code: String) async throws -> [Video] {
        let fresh = try await videosService.fetchVideos(forCode: code)
        saveToCache(videos: fresh)
        return fresh
    }
    
    /// Removes a video from the cache by its ID
    func removeFromCache(id: String) {
        guard var cached = loadFromCache() else { return }
        cached.removeAll { $0.id == id }
        saveToCache(videos: cached)
    }
    
    /// Deletes all cached videos by removing the cache file
    func clearCache() {
        guard let url = cacheURL() else { return }
        do {
            try FileManager.default.removeItem(at: url)
            print("[CachedVideosService] Cache cleared.")
        } catch {
            print("Failed to remove cache file: \(error)")
        }
    }

    // MARK: - Caching Logic
    private func cacheURL() -> URL? {
        do {
            let documentsDirectory = try FileManager.default.url(for: .documentDirectory,
                                                                 in: .userDomainMask,
                                                                 appropriateFor: nil,
                                                                 create: true)
            return documentsDirectory.appendingPathComponent(cacheFileName)
        } catch {
            print("Failed to get documents directory: \(error)")
            return nil
        }
    }
    
    private func loadFromCache() -> [Video]? {
        guard let url = cacheURL(),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        
        do {
            let videos = try JSONDecoder().decode([Video].self, from: data)
            return videos
        } catch {
            print("Failed to decode cached videos: \(error)")
            return nil
        }
    }

    private func saveToCache(videos: [Video]) {
        guard let url = cacheURL() else { return }
        
        do {
            let data = try JSONEncoder().encode(videos)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("Failed to save videos to cache: \(error)")
        }
    }
}
