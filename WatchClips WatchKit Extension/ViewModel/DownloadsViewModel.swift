import SwiftUI
import WatchKit

// MARK: - DownloadManagerDelegate
protocol DownloadManagerDelegate: AnyObject {
    func downloadDidUpdateProgress(videoId: String, receivedBytes: Int64, totalBytes: Int64)
    func downloadDidComplete(videoId: String, localFileURL: URL?)
    func downloadDidFail(videoId: String, error: Error)
}

// MARK: - SegmentedDownloadManagerDelegate
protocol SegmentedDownloadManagerDelegate: AnyObject {
    func segmentedDownloadDidUpdateProgress(videoId: String, progress: Double)
    func segmentedDownloadDidComplete(videoId: String, fileURL: URL)
    func segmentedDownloadDidFail(videoId: String, error: any Error)
}

// MARK: - DownloadsViewModel
@MainActor
class DownloadsViewModel: ObservableObject {
    // MARK: - Published Properties
    @EnvironmentObject var sharedVM: SharedVideosViewModel
    
    @Published var videos: [DownloadedVideo] = []
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let cachedVideosService: CachedVideosService
    private let store = DownloadsStore()
    
    /// Our new parallel chunk-based manager (with two-host splitting).
    private let bgManager = SegmentedDownloadManager.shared

    init(cachedVideosService: CachedVideosService) {
        self.cachedVideosService = cachedVideosService
        
        // Become the chunk-based delegate
        bgManager.segmentedDelegate = self
        
        // (Optional) Also handle old-style callbacks:
        bgManager.oldDelegate = self
        
        print("[DownloadsViewModel] Initialized with CachedVideosService.")
    }
    
    // MARK: - Local Persistence
    
    func loadLocalDownloads() {
        print("[DownloadsViewModel] Loading locally persisted downloads from store...")
        self.videos = store.loadDownloads()
        print("[DownloadsViewModel] Loaded \(videos.count) local downloads from store.")
    }
    
    func persist() {
        print("[DownloadsViewModel] Persisting downloads to store...")
        store.saveDownloads(videos)
        print("[DownloadsViewModel] Persist complete.")
    }
    
    // MARK: - Start / Pause / Delete

    func startOrResumeDownload(_ item: DownloadedVideo) {
        guard item.downloadStatus != .downloading && item.downloadStatus != .completed else {
            print("[DownloadsViewModel] \(item.id) is already downloading or completed.")
            return
        }
        
        guard let remoteURL = buildRemoteURL(item.video) else {
            print("[DownloadsViewModel] [ERROR] Could not build remote URL for video \(item.id).")
            return
        }

        print("[DownloadsViewModel] Initiating startOrResumeDownload for videoId: \(item.id).")
        
        DispatchQueue.main.async {
            // Mark it as "downloading" in our local model
            self.updateStatus(item.id, status: .downloading, errorMessage: nil)
            
            // Let the chunk-based manager do the rest
            self.bgManager.resumeDownload(videoId: item.id, from: remoteURL)
        }
    }
    
    func pauseDownload(_ item: DownloadedVideo) {
        print("[DownloadsViewModel] Pausing download for \(item.id).")
        
        DispatchQueue.main.async {
            self.bgManager.cancelDownload(videoId: item.id)
            self.updateStatus(item.id, status: .paused, errorMessage: nil)
        }
    }
    
    /// **Deletes both** the final `.mp4` **and** any partial data if the download is in progress.
    func deleteVideo(_ item: DownloadedVideo) {
        print("[DownloadsViewModel] Deleting local file (and partial data) for \(item.id).")
        
        // 1) Tell the manager to remove everything (cancel + delete files + metadata).
        bgManager.removeDownloadCompletely(videoId: item.id)
        
        // 2) Reset status in local model
        var updated = item
        updated.downloadStatus = .notStarted
        updated.downloadedBytes = 0
        updated.errorMessage = nil

        // 3) Update local array
        if let index = videos.firstIndex(where: { $0.id == item.id }) {
            videos[index] = updated
            print("[DownloadsViewModel] Reset download status for video \(item.id).")
        } else {
            print("[DownloadsViewModel] [ERROR] Could not find video \(item.id) in current list to delete.")
        }
        
        // 4) Persist changes
        persist()
    }
    
    func resumeInProgressDownloads() {
        print("[DownloadsViewModel] Attempting to resume in-progress downloads (chunk-based).")

        for item in videos where item.downloadStatus == .downloading {
            let isActive = bgManager.isTaskActive(videoId: item.id)
            if !isActive {
                guard let remoteURL = buildRemoteURL(item.video) else {
                    print("[DownloadsViewModel] [ERROR] Could not build remote URL for \(item.id). Skipping resume.")
                    continue
                }
                
                print("[DownloadsViewModel] Re-queuing \(item.id) because it was .downloading but not active in manager.")
                bgManager.startDownload(videoId: item.id, from: remoteURL)
            }
        }
    }
    
    // MARK: - NEW: onAppearCheckForURLChanges
    
    /// Call this (e.g. from a SwiftUI View's `onAppear`) to ensure each video's URL is up-to-date.
    /// If the URL has changed from what the manager has on file, it will compare which leftover portion is smaller,
    /// and pick the smaller path.
    func onAppearCheckForURLChanges() {
        print("[DownloadsViewModel] onAppear => Checking for any changed URLs in all videos.")
        for item in videos {
            // Build the current/expected remote URL
            guard let remoteURL = buildRemoteURL(item.video) else {
                print("[DownloadsViewModel] [ERROR] Could not build remote URL for \(item.id). Skipping check.")
                continue
            }
            
            if item.downloadStatus == .downloading {
                // Simply call startDownload. If there's no change, the manager does nothing.
                // If there *is* a change, it triggers the HEAD/compare logic automatically.
                bgManager.startDownload(videoId: item.id, from: remoteURL)
            }
        }
    }
    
    // MARK: - Helpers
    
    func progress(for item: DownloadedVideo) -> Double {
        guard item.totalBytes > 0 else { return 0.0 }
        return min(1.0, Double(item.downloadedBytes) / Double(item.totalBytes))
    }

    func isFullyDownloaded(_ item: DownloadedVideo) -> Bool {
        item.downloadStatus == .completed
    }

    private func updateStatus(_ videoId: String,
                              status: DownloadStatus,
                              receivedBytes: Int64? = nil,
                              totalBytes: Int64? = nil,
                              errorMessage: String? = nil) {
        guard let idx = videos.firstIndex(where: { $0.id == videoId }) else {
            print("[DownloadsViewModel] [ERROR] No matching video found for \(videoId).")
            return
        }
        
        var v = videos[idx]
        v.downloadStatus = status
        v.downloadedBytes = receivedBytes ?? v.downloadedBytes
        v.totalBytes = totalBytes ?? v.totalBytes
        v.errorMessage = errorMessage
        videos[idx] = v
        
        print("[DownloadsViewModel] Updated status for \(videoId) => \(status). "
              + "downloadedBytes=\(v.downloadedBytes), totalBytes=\(v.totalBytes), error=\(errorMessage ?? "nil")")
        
        persist()
    }

    private func buildRemoteURL(_ video: Video) -> URL? {
        // Example base URL - just one domain for the "primary" path
        guard let base = URL(string: "https://dwxvsu8u3eeuu.cloudfront.net") else {
            print("[DownloadsViewModel] [ERROR] Invalid base URL string.")
            return nil
        }
        return base.appendingPathComponent(video.filename)
    }
}

// MARK: - SegmentedDownloadManagerDelegate
extension DownloadsViewModel: SegmentedDownloadManagerDelegate {
    func segmentedDownloadDidUpdateProgress(videoId: String, progress: Double) {
        Task { @MainActor in
            guard let idx = videos.firstIndex(where: { $0.id == videoId }) else { return }
            
            let item = videos[idx]
            let total = item.totalBytes
            let current = Int64(Double(total) * progress)
            
            updateStatus(videoId, status: .downloading,
                         receivedBytes: current,
                         totalBytes: total)
            
            print("[DownloadsViewModel] [Segmented] \(videoId) progress: \(progress * 100)%")
        }
    }
    
    func segmentedDownloadDidComplete(videoId: String, fileURL: URL) {
        Task { @MainActor in
            print("[DownloadsViewModel] [Segmented] \(videoId) => Completed, file: \(fileURL.lastPathComponent)")
            updateStatus(videoId, status: .completed, receivedBytes: nil, totalBytes: nil)
            
            // Optionally trigger a local notification WITH the full `Video` object
            if let item = videos.first(where: { $0.id == videoId }) {
                let title = item.video.title ?? "(Untitled)"
                
                // Pass the entire `Video` to NotificationManager
                NotificationManager.shared.scheduleLocalNotification(
                    title: title,
                    body: "Your video is ready to watch!",
                    video: item.video
                ) { success in
                    print("[DownloadsViewModel] Notification scheduled? \(success)")
                }
            }
        }
    }
    
    func segmentedDownloadDidFail(videoId: String, error: any Error) {
        Task { @MainActor in
            let message = "[DownloadsViewModel] [Segmented] \(videoId) => Failed: \(error.localizedDescription)"
            print(message)
            updateStatus(videoId, status: .error, errorMessage: error.localizedDescription)
        }
    }
}

// MARK: - Old DownloadManagerDelegate
extension DownloadsViewModel: DownloadManagerDelegate {
    func downloadDidUpdateProgress(videoId: String, receivedBytes: Int64, totalBytes: Int64) {
        Task { @MainActor in
            print("[DownloadsViewModel] [OldDelegate] \(videoId) progress: \(receivedBytes)/\(totalBytes)")
            updateStatus(videoId, status: .downloading,
                         receivedBytes: receivedBytes,
                         totalBytes: totalBytes)
        }
    }
    
    func downloadDidComplete(videoId: String, localFileURL: URL?) {
        Task { @MainActor in
            print("[DownloadsViewModel] [OldDelegate] \(videoId) => Complete, file: \(localFileURL?.lastPathComponent ?? "nil")")
            updateStatus(videoId, status: .completed)
        }
    }
    
    func downloadDidFail(videoId: String, error: Error) {
        Task { @MainActor in
            let msg = "[DownloadsViewModel] [OldDelegate] \(videoId) => Fail: \(error.localizedDescription)"
            print(msg)
            updateStatus(videoId, status: .error, errorMessage: error.localizedDescription)
        }
    }
}

extension DownloadsViewModel {
    /// Return the `DownloadedVideo` item for a given `Video`,
    /// or create one if it doesn't exist in our local array.
    func itemFor(video: Video) -> DownloadedVideo {
        if let existing = videos.first(where: { $0.id == video.id }) {
            // Return updated version if needed
            return DownloadedVideo(
                video: video,
                downloadStatus: existing.downloadStatus,
                downloadedBytes: existing.downloadedBytes,
                totalBytes: existing.totalBytes,
                errorMessage: existing.errorMessage
            )
        } else {
            let newDownload = DownloadedVideo(
                video: video,
                downloadStatus: .notStarted,
                downloadedBytes: 0,
                totalBytes: video.size ?? 0,
                errorMessage: nil
            )
            
            DispatchQueue.main.async {
                self.videos.append(newDownload)
            }
            
            return newDownload
        }
    }
}
