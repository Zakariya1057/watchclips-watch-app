import Foundation
import Combine

final class PlaybackProgressService: ObservableObject {
    static let shared = PlaybackProgressService()
    
    /// The ID of the most recently updated video (in-memory)
    @Published private(set) var lastPlayedVideoId: String?
    
    private init() {
        // Optionally sync from DB on app launch so it's populated if set previously
        self.lastPlayedVideoId = getMostRecentlyUpdatedVideoId()
    }
    
    /// Set the progress for a given video, along with the current timestamp
    func setProgress(videoId: String, progress: Double) {
        let timestamp = Date().timeIntervalSince1970
        PlaybackProgressRepository.shared.setProgress(
            videoId: videoId,
            progress: progress,
            updatedAt: timestamp
        )
        // Update in-memory last played ID
        self.lastPlayedVideoId = videoId
    }
    
    /// Get the progress and last update time for a given video
    func getProgress(videoId: String) -> (progress: Double, updatedAt: Date)? {
        guard let result = PlaybackProgressRepository.shared.getProgress(videoId: videoId) else {
            return nil
        }
        let date = Date(timeIntervalSince1970: result.updatedAt)
        return (result.progress, date)
    }
    
    /// Fetch from DB: video ID with most recently updated progress
    func getMostRecentlyUpdatedVideoId() -> String? {
        PlaybackProgressRepository.shared.getMostRecentlyUpdatedVideoId()
    }
    
    /// Clear a specific video's progress
    func clearProgress(videoId: String) {
        PlaybackProgressRepository.shared.clearProgress(videoId: videoId)
    }
    
    /// Clear progress for all videos
    func clearAllProgress() {
        PlaybackProgressRepository.shared.clearAllProgress()
        // TODO: Sort this out
        self.lastPlayedVideoId = nil
    }
}
