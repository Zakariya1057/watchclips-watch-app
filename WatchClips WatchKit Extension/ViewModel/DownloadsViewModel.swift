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
    @Published var videos: [DownloadedVideo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Optimizing Checker
    @Published private(set) var isMonitoringProcessing = false
    private var checkProcessingTask: Task<Void, Never>? = nil
    
    // MARK: - Private Properties
    private let cachedVideosService: CachedVideosService
    private let store = DownloadsStore()
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
        // (Optional) Also handle old-style callbacks:
        bgManager.oldDelegate = self
        
        print("[DownloadsViewModel] Initialized with CachedVideosService & SettingsStore.")
        
        // Load previously saved downloads on initialization
        loadLocalDownloads()
    }
    
    // MARK: - Public API
    
    // ---------------------------
    //     OPTIMIZING CHECKER
    // ---------------------------
    func startProcessingCheckerIfNeeded(code: String) {
        guard !isMonitoringProcessing else {
            print("[DownloadsViewModel] startProcessingCheckerIfNeeded => Already monitoring; returning early.")
            return
        }
        
        isMonitoringProcessing = true
        print("[DownloadsViewModel] startProcessingCheckerIfNeeded => Starting optimizing checker (code=\(code)).")
        
        checkProcessingTask = Task {
            while !Task.isCancelled {
                // Check which videos are still "optimizing"
                let optimizingVideos = sharedVM.videos.filter { $0.isOptimizing }
                if optimizingVideos.isEmpty {
                    print("[DownloadsViewModel] Checker => No videos currently optimizing. Stopping checker.")
                    stopProcessingChecker()
                    return
                }
                
                print("[DownloadsViewModel] Checker => Found \(optimizingVideos.count) video(s) still optimizing. Will recheck after delay.")
                
                // Sleep ~2 minutes
                do {
                    try await Task.sleep(nanoseconds: 120_000_000_000)
                } catch {
                    print("[DownloadsViewModel] Checker => Task canceled during sleep.")
                    break
                }
                
                if !Task.isCancelled {
                    print("[DownloadsViewModel] Checker => Refreshing videos now (code=\(code)).")
                    await sharedVM.refreshVideos(code: code, forceRefresh: true)
                    
                    print("[DownloadsViewModel] Checker => Checking for updated URLs.")
                    let anyUrlsChanged = onAppearCheckForURLChanges()
                    
                    if anyUrlsChanged {
                        print("[DownloadsViewModel] Checker => URL changes detected. Stopping checker.")
                        stopProcessingChecker()
                    } else {
                        print("[DownloadsViewModel] Checker => No URL changes detected; continuing.")
                    }
                } else {
                    print("[DownloadsViewModel] Checker => Task canceled after refresh.")
                }
            }
            
            if Task.isCancelled {
                print("[DownloadsViewModel] Checker => Exited loop because Task was canceled.")
                stopProcessingChecker()
            }
        }
    }

    func stopProcessingChecker() {
        print("[DownloadsViewModel] stopProcessingChecker => Canceling checker task and resetting flags.")
        checkProcessingTask?.cancel()
        checkProcessingTask = nil
        isMonitoringProcessing = false
    }
    
    // ---------------------------
    //     VIDEO / DOWNLOADS
    // ---------------------------
    
    func setVideos(newVideos: [Video]) {
        let downloadedVideo = store.loadDownloads()
        
        videos = newVideos.map { video in
            if let existing = downloadedVideo.first(where: { $0.video.id == video.id }) {
                return existing
            } else {
                return DownloadedVideo(
                    video: video,
                    downloadStatus: .notStarted,
                    downloadedBytes: 0,
                    totalBytes: video.size ?? 0,
                    errorMessage: nil,
                    lastDownloadURL: URL(string: video.filename)
                )
            }
        }
        if let code = newVideos.first?.code {
            startProcessingCheckerIfNeeded(code: code)
        }
    }
    
    func loadLocalDownloads() {
        print("[DownloadsViewModel] Loading locally persisted downloads from store...")
        videos = store.loadDownloads()
        print("[DownloadsViewModel] Loaded \(videos.count) local downloads from store.")
    }
    
    func persist() {
        print("[DownloadsViewModel] Persisting downloads to store...")
        store.saveDownloads(videos)
        print("[DownloadsViewModel] Persist complete.")
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
                print("[DownloadsViewModel] Resuming chunk-based download for \(item.id)...")
                bgManager.resumeDownload(videoId: item.id, from: remoteURL)
            }
        }
    }
    
    /// Checks each downloadedVideo against the updated `sharedVM.videos`.
    /// If a video changed from isOptimized = true to false, and user wants notifications, send it.
    /// If a URL changed, we resume downloading.
    ///
    /// Returns `true` if any URL changed and was resumed, otherwise `false`.
    @discardableResult
    func onAppearCheckForURLChanges() -> Bool {
        print("[DownloadsViewModel] onAppear => Checking for any changed URLs in all videos.")
        var anyUrlsChanged = false
        
        for downloadedVideo in videos {
            guard let updatedVideo = sharedVM.videos.first(where: { $0.id == downloadedVideo.video.id }) else {
                // If not found in sharedVM, it might have been removed or something changed
                print("[DownloadsViewModel] onAppearCheckForURLChanges => Canceling download, file removed remotely (\(downloadedVideo.id))")
                bgManager.cancelDownload(videoId: downloadedVideo.id)
                continue
            }
            
            // 1) Check if video changed significantly (size, name, status, etc.)
            let oldVideo = downloadedVideo.video
            let newVideo = updatedVideo
            
            let oldFilename = oldVideo.filename
            let newFilename = newVideo.filename
            
            // (A) If the entire Video object changed, update local model
            if oldVideo != newVideo {
                print("[DownloadsViewModel] onAppearCheckForURLChanges => Video changed! (id=\(downloadedVideo.id))")
                
                updateStatus(
                    downloadedVideo.id,
                    status: downloadedVideo.downloadStatus,
                    receivedBytes: 0,
                    totalBytes: newVideo.size,
                    errorMessage: nil,
                    video: newVideo
                )
                persist()
                
                // (B) If it changed from `postProcessingSuccess` => not success,
                // and user wants notifications, schedule one
                if oldVideo.isOptimizing == true && newVideo.isOptimizing == false {
                    if settingsStore.settings.notifyOnOptimize {
                        notifyVideoNowOptimized(newVideo)
                    }
                }
            }
            
            // 2) Check if URL changed => resume if needed
            let isFilenameChanged = (newFilename != oldFilename)
            let isInProgress = (downloadedVideo.downloadStatus == .downloading)
            
            if isFilenameChanged || downloadedVideo.errorMessage != nil {
                print("[DownloadsViewModel] onAppearCheckForURLChanges => (\(downloadedVideo.id))'s URL changed or had an error. Resuming download.")
                
                guard let remoteURL = buildRemoteURL(newVideo) else {
                    print("[DownloadsViewModel] [ERROR] Could not build remote URL for \(downloadedVideo.id). Skipping.")
                    continue
                }
                
                if isInProgress {
                    anyUrlsChanged = true
                    bgManager.resumeDownload(videoId: downloadedVideo.id, from: remoteURL)
                }
            } else {
                print("[DownloadsViewModel] onAppearCheckForURLChanges => (\(downloadedVideo.id))'s URL unchanged or not in progress. No action taken.")
            }
        }
        
        return anyUrlsChanged
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
        
        persist()
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
        
        stopProcessingChecker()
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
            
            updateStatus(
                videoId,
                status: .downloading,
                receivedBytes: current,
                totalBytes: total
            )
            
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

// MARK: - Old DownloadManagerDelegate
extension DownloadsViewModel: DownloadManagerDelegate {
    func downloadDidUpdateProgress(videoId: String, receivedBytes: Int64, totalBytes: Int64) {
        Task { @MainActor in
            print("[DownloadsViewModel] [OldDelegate] \(videoId) => progress: \(receivedBytes)/\(totalBytes)")
            updateStatus(
                videoId,
                status: .downloading,
                receivedBytes: receivedBytes,
                totalBytes: totalBytes
            )
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
