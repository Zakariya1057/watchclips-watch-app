import SwiftUI
import WatchKit

// MARK: - SegmentedDownloadManagerDelegate
protocol SegmentedDownloadManagerDelegate: AnyObject {
    func segmentedDownloadDidUpdateProgress(videoId: String, receivedBytes: Int64, totalBytes: Int64, progress: Double)
    func segmentedDownloadDidComplete(videoId: String, fileURL: URL)
    func segmentedDownloadDidFail(videoId: String, error: any Error)
}

// MARK: - DownloadsViewModel
@MainActor
class DownloadsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var videos: [DownloadedVideo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Optimizing Checker
    @Published private(set) var isMonitoringProcessing = false
    private var checkProcessingTask: Task<Void, Never>? = nil
    
    // MARK: - Private Properties
    private let cachedVideosService: CachedVideosService
    private let bgManager = SegmentedDownloadManager.shared
    
    private let sharedVM: SharedVideosViewModel
    private let settingsStore: SettingsStore  // <--- Use this to decide whether to send notifications
    
    private var code: String? {
        return sharedVM.loggedInState?.code
    }
    
    // MARK: - Init
    init(
        cachedVideosService: CachedVideosService,
        sharedVM: SharedVideosViewModel,
        settingsStore: SettingsStore
    ) {
        self.cachedVideosService = cachedVideosService
        self.sharedVM = sharedVM
        self.settingsStore = settingsStore
        
        // Become the chunk-based delegate
        bgManager.segmentedDelegate = self
        
        print("[DownloadsViewModel] Initialized with CachedVideosService & SettingsStore.")
        
        // Load previously saved downloads on initialization
        loadLocalDownloads()
    }
    
    // ---------------------------
    //     VIDEO / DOWNLOADS
    // ---------------------------
    
    func setVideos(newVideos: [Video]) {
        // 1) Load the existing local DownloadedVideos from storage
        let localDownloads = DownloadsStore.shared.loadDownloads()
        
        // 2) For each new Video from the server:
        videos = newVideos.map { serverVideo in
            
            // 3) Check if we already have a matching DownloadedVideo
            if var existing = localDownloads.first(where: { $0.video.id == serverVideo.id }) {
                // -- P R E S E R V E  local fields (downloadStatus, downloadedBytes, etc.) --
                // but update the underlying Video object (title, filename, etc.)
                
                existing.video = serverVideo
                
                // Also update totalBytes if the server’s size is different
                // (but keep existing.downloadedBytes, status, etc. intact)
                existing.totalBytes = serverVideo.size ?? existing.totalBytes
                
                // Return the merged DownloadedVideo
                return existing
                
            } else {
                // 4) If no existing record, create a fresh DownloadedVideo
                return DownloadedVideo(
                    video: serverVideo,
                    downloadStatus: .notStarted,
                    downloadedBytes: 0,
                    totalBytes: serverVideo.size ?? 0,
                    errorMessage: nil,
                    lastDownloadURL: URL(string: serverVideo.filename)
                )
            }
        }
    }
    
    func loadLocalDownloads() {
        print("[DownloadsViewModel] Loading locally persisted downloads from store...")
        videos = DownloadsStore.shared.loadDownloads()
        print("[DownloadsViewModel] Loaded \(videos.count) local downloads from store.")
    }
    
    func removeDownload(videoId: String) {
        DownloadsStore.shared.removeById(videoId: videoId)
    }

    func saveDownload(download: DownloadedVideo) {
        DownloadsStore.shared.saveDownload(download: download)
    }
    
    func startOrResumeDownload(_ item: DownloadedVideo) {
        guard item.downloadStatus != .completed else {
            print("[DownloadsViewModel] \(item.id) is already completed.")
            return
        }
        guard let remoteURL = buildRemoteURL(item.video) else {
            print("[DownloadsViewModel] [ERROR] Could not build remote URL for video \(item.id).")
            return
        }

        print("[DownloadsViewModel] Initiating startOrResumeDownload for videoId: \(item.id).")
        
        Task {
            updateStatus(item.id, status: .downloading, errorMessage: nil)
            bgManager.resumeDownload(videoId: item.id, from: remoteURL)
        }
    }
    
    func pauseDownload(_ item: DownloadedVideo) {
        print("[DownloadsViewModel] Pausing download for \(item.id).")
        Task {
            bgManager.cancelDownload(videoId: item.id)
            updateStatus(item.id, status: .paused, errorMessage: nil)
        }
    }

    func deleteVideo(_ item: DownloadedVideo) {
        print("[DownloadsViewModel] Deleting local file (and partial data) for \(item.id).")
        
        bgManager.removeDownloadCompletely(videoId: item.id)
        
        var updated = item
        updated.downloadStatus = .notStarted
        updated.downloadedBytes = 0
        updated.errorMessage = nil
        updated.lastDownloadURL = nil

        if let index = videos.firstIndex(where: { $0.id == item.id }) {
            videos[index] = updated
            print("[DownloadsViewModel] Reset download status for video \(item.id).")
        } else {
            print("[DownloadsViewModel] [ERROR] Could not find video \(item.id) in current list to delete.")
        }
        
        removeDownload(videoId: item.id)
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
                print("[DownloadsViewModel] Resuming chunk-based download for \(item.id)...")
                bgManager.resumeDownload(videoId: item.id, from: remoteURL)
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
    
    func itemFor(video: Video) -> DownloadedVideo {
        if let existing = videos.first(where: { $0.video.id == video.id }) {
            return existing
        } else {
            let newDownload = DownloadedVideo(
                video: video,
                downloadStatus: .notStarted,
                downloadedBytes: 0,
                totalBytes: video.size ?? 0,
                errorMessage: nil,
                lastDownloadURL: URL(string: video.filename)
            )
            
            DispatchQueue.main.async {
                self.videos.append(newDownload)
            }
            
            return newDownload
        }
    }
    
    // Update local array & persist
    private func updateStatus(
        _ videoId: String,
        status: DownloadStatus,
        receivedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        errorMessage: String? = nil,
        video: Video? = nil
    ) {
        guard let idx = videos.firstIndex(where: { $0.id == videoId }) else {
            print("[DownloadsViewModel] [ERROR] No matching video found for \(videoId).")
            return
        }
        
        var v = videos[idx]
        v.downloadStatus = status
        v.downloadedBytes = receivedBytes ?? v.downloadedBytes
        v.totalBytes = totalBytes ?? v.totalBytes
        v.errorMessage = errorMessage
        
        if let video = video {
            v.video = video
        }
        
        videos[idx] = v
        
        print("[DownloadsViewModel] Updated status for \(videoId) => \(status). downloadedBytes=\(v.downloadedBytes), totalBytes=\(v.totalBytes), error=\(errorMessage ?? "nil")")
        
        saveDownload(download: v)
    }

    private func buildRemoteURL(_ video: Video) -> URL? {
        guard let base = URL(string: "https://dwxvsu8u3eeuu.cloudfront.net") else {
            print("[DownloadsViewModel] [ERROR] Invalid base URL string.")
            return nil
        }
        return base.appendingPathComponent(video.filename)
    }

    private func notifyVideoNowOptimized(_ video: Video) {
        let title = video.title ?? "WatchClips"
        let body = "\(title) is now optimized! You can download it quickly with a smaller file size."

        NotificationManager.shared.scheduleLocalNotification(
            title: title,
            body: body,
            video: video,
            action: .openDownloads
        ) { success in
            print("[DownloadsViewModel] notifyVideoNowOptimized => Notification scheduled? \(success)")
        }
    }

}

// MARK: - SegmentedDownloadManagerDelegate
extension DownloadsViewModel: SegmentedDownloadManagerDelegate {
    func segmentedDownloadDidUpdateProgress(videoId: String, receivedBytes: Int64, totalBytes: Int64, progress: Double) {
        Task { @MainActor in
            updateStatus(
                videoId,
                status: .downloading,
                receivedBytes: receivedBytes,
                totalBytes: totalBytes
            )
            
            print("Received: \(receivedBytes)")
            
            print("[DownloadsViewModel] [Segmented] \(videoId) => progress: \((progress * 100).rounded())%")
        }
    }
    
    func segmentedDownloadDidComplete(videoId: String, fileURL: URL) {
        Task { @MainActor in
            print("[DownloadsViewModel] [Segmented] \(videoId) => Completed, file: \(fileURL.lastPathComponent)")
            updateStatus(videoId, status: .completed)
            
            // If user wants "Notify on Download", schedule a notification
            if let item = videos.first(where: { $0.id == videoId }) {
                if settingsStore.settings.notifyOnDownload {
                    let title = item.video.title ?? "(Untitled)"
                    NotificationManager.shared.scheduleLocalNotification(
                        title: title,
                        body: "Your video is ready to watch!",
                        video: item.video,
                        action: .openVideoPlayer
                    ) { success in
                        print("[DownloadsViewModel] Notification scheduled on download complete? \(success)")
                    }
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
