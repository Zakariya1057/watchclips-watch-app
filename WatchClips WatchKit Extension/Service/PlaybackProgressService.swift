import Foundation

final class PlaybackProgressService {
    static let shared = PlaybackProgressService()
    
    private let userDefaults = UserDefaults.standard
    
    private func progressKey(forVideoId videoId: String) -> String {
        return "PlaybackProgress-\(videoId)"
    }
    
    private func timestampKey(forVideoId videoId: String) -> String {
        return "PlaybackTimestamp-\(videoId)"
    }
    
    /// Return the stored playback progress for a video
    func getProgress(for videoId: String) -> Double? {
        let key = progressKey(forVideoId: videoId)
        return userDefaults.object(forKey: key) == nil ? nil : userDefaults.double(forKey: key)
    }
    
    /// Store both progress and a 'last updated' timestamp
    func setProgress(_ progress: Double, for videoId: String) {
        userDefaults.set(progress, forKey: progressKey(forVideoId: videoId))
        let timestamp = Date().timeIntervalSince1970
        userDefaults.set(timestamp, forKey: timestampKey(forVideoId: videoId))
    }
    
    /// Clear a single video's progress
    func clearProgress(for videoId: String) {
        userDefaults.removeObject(forKey: progressKey(forVideoId: videoId))
        userDefaults.removeObject(forKey: timestampKey(forVideoId: videoId))
    }
    
    /// Clear progress for all videos
    func clearAllProgress() {
        for key in userDefaults.dictionaryRepresentation().keys {
            if key.hasPrefix("PlaybackProgress-") || key.hasPrefix("PlaybackTimestamp-") {
                userDefaults.removeObject(forKey: key)
            }
        }
    }
    
    /// Get the video ID with the most recent timestamp
    func getMostRecentlyUpdatedVideoId() -> String? {
        let allKeys = userDefaults.dictionaryRepresentation().keys
        
        let timestampKeys = allKeys.filter { $0.hasPrefix("PlaybackTimestamp-") }
        
        var mostRecentVideoId: String?
        var mostRecentTimestamp: TimeInterval = 0
        
        for key in timestampKeys {
            let videoId = key.replacingOccurrences(of: "PlaybackTimestamp-", with: "")
            let timestamp = userDefaults.double(forKey: key)
            if timestamp > mostRecentTimestamp {
                mostRecentTimestamp = timestamp
                mostRecentVideoId = videoId
            }
        }
        
        return mostRecentVideoId
    }
}
