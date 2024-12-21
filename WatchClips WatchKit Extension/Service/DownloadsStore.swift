import Foundation

class DownloadsStore {
    private let userDefaultsKey = "downloads_info"

    /// Load `[DownloadedVideo]` from UserDefaults
    func loadDownloads() -> [DownloadedVideo] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return []
        }
        do {
            let decoded = try JSONDecoder().decode([DownloadedVideo].self, from: data)
            return decoded
        } catch {
            print("[DownloadsStore] decode error: \(error)")
            return []
        }
    }
    
    /// Save `[DownloadedVideo]` to UserDefaults
    func saveDownloads(_ downloads: [DownloadedVideo]) {
        do {
            let data = try JSONEncoder().encode(downloads)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("[DownloadsStore] encode error: \(error)")
        }
    }
}

extension DownloadsStore {
    /// Returns true if the stored item for `videoId` is found with a .completed downloadStatus
    func isDownloaded(videoId: String) -> Bool {
        let allDownloads = loadDownloads()
        guard let item = allDownloads.first(where: { $0.id == videoId }) else {
            return false
        }
        return item.downloadStatus == .completed
    }
}

