import Foundation

final class PlaybackProgressService {
    static let shared = PlaybackProgressService()
    
    /// Set the progress for a given video, along with the current timestamp
    func setProgress(videoId: String, progress: Double) {
        let timestamp = Date().timeIntervalSince1970
        PlaybackProgressRepository.shared.setProgress(
            videoId: videoId,
            progress: progress,
            updatedAt: timestamp
        )
    }
    
    /// Get the progress and last update time for a given video
    func getProgress(videoId: String) -> (progress: Double, updatedAt: Date)? {
        guard let result = PlaybackProgressRepository.shared.getProgress(videoId: videoId) else {
            return nil
        }
        // Convert the raw Double timestamp into a Date
        let date = Date(timeIntervalSince1970: result.updatedAt)
        return (result.progress, date)
    }
    
    /// Fetch the video ID with the most recently updated progress
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
    }
}
