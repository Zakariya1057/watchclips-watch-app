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
