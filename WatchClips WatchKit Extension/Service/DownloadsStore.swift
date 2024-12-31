import Foundation

class DownloadsStore {
    // Instead of userDefaultsKey, we have a repository
    private let repository = DownloadsRepository.shared

    /// Load `[DownloadedVideo]` from the Downloads table
    func loadDownloads() -> [DownloadedVideo] {
        return repository.loadAll()
    }
    
    /// Save `[DownloadedVideo]` to the Downloads table
    func saveDownloads(_ downloads: [DownloadedVideo]) {
        repository.saveAll(downloads)
    }
    
    func removeById(videoId: String) -> Void {
        return repository.removeById(videoId)
    }

    /// Clear all downloads from local storage
    func clearAllDownloads() {
        repository.removeAll()
        print("[DownloadsStore] Cleared all downloads in SQLite.")
    }
}

extension DownloadsStore {
    /// Returns true if the stored item for `videoId` has a `.completed` status
    func isDownloaded(videoId: String) -> Bool {
        let allDownloads = loadDownloads()
        guard let item = allDownloads.first(where: { $0.id == videoId }) else {
            return false
        }
        return item.downloadStatus == .completed
    }
}
