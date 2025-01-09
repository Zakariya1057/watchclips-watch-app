//
//  DownloadsViewModel.swift
//  Example Project
//
//  Created by You on [Date].
//

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
    
    // MARK: - Private Properties
    private var sharedVM: SharedVideosViewModel
    private let cachedVideosService: CachedVideosService
    private let store = DownloadsStore()
    
    /// Parallel chunk-based manager (with two-host splitting).
    private let bgManager = SegmentedDownloadManager.shared

    // MARK: - Init
    init(cachedVideosService: CachedVideosService, sharedVM: SharedVideosViewModel) {
        self.cachedVideosService = cachedVideosService
        self.sharedVM = sharedVM
        
        // Become the chunk-based delegate
        bgManager.segmentedDelegate = self
        
        // (Optional) Also handle old-style callbacks:
        bgManager.oldDelegate = self
        
        print("[DownloadsViewModel] Initialized with CachedVideosService.")
        
        // Load previously saved downloads on initialization:
        loadLocalDownloads()
    }
    
    // MARK: - Public API
    
    /// Updates the local `videos` array with new data (or reuses existing items).
    func setVideos(newVideos: [Video]) {
        let downloadedVideo = store.loadDownloads()
        
        videos = newVideos.map { video in
            if let existing = downloadedVideo.first(where: { $0.video.id == video.id }) {
                return existing
            } else {
                // Otherwise, create a fresh DownloadedVideo
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
    }
    
    /// Loads the persisted downloads from store.
    func loadLocalDownloads() {
        print("[DownloadsViewModel] Loading locally persisted downloads from store...")
        videos = store.loadDownloads()
        print("[DownloadsViewModel] Loaded \(videos.count) local downloads from store.")
    }
    
    /// Persists current `videos` state to disk.
    func persist() {
        print("[DownloadsViewModel] Persisting downloads to store...")
        store.saveDownloads(videos)
        print("[DownloadsViewModel] Persist complete.")
    }

    /// Starts or resumes a download for the given `DownloadedVideo` item.
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
            // Mark it as "downloading" in our local model
            updateStatus(item.id, status: .downloading, errorMessage: nil)
            
            // The chunk-based manager handles partial data if it exists
            bgManager.resumeDownload(videoId: item.id, from: remoteURL)
        }
    }
    
    /// Pauses an ongoing download for the given `DownloadedVideo` item.
    func pauseDownload(_ item: DownloadedVideo) {
        print("[DownloadsViewModel] Pausing download for \(item.id).")
        Task {
            bgManager.cancelDownload(videoId: item.id)
            updateStatus(item.id, status: .paused, errorMessage: nil)
        }
    }

    /// Deletes all local file data for a given `DownloadedVideo` (both final file & partial data).
    func deleteVideo(_ item: DownloadedVideo) {
        print("[DownloadsViewModel] Deleting local file (and partial data) for \(item.id).")
        
        // 1) Tell the manager to remove everything
        bgManager.removeDownloadCompletely(videoId: item.id)
        
        // 2) Reset status in local model
        var updated = item
        updated.downloadStatus = .notStarted
        updated.downloadedBytes = 0
        updated.errorMessage = nil
        updated.lastDownloadURL = nil

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
    
    /// Resumes downloads that were in progress but may not be actively running in the manager.
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
    
    /// Ensures each video's URL is up-to-date; if changed, resumes download with the new URL.
    func onAppearCheckForURLChanges() {
        print("[DownloadsViewModel] onAppear => Checking for any changed URLs in all videos.")
        
        for downloadedVideo in videos {
            guard let updatedVideo = sharedVM.videos.first(where: { $0.id == downloadedVideo.video.id }) else {
                // If not found in sharedVM, cancel any ongoing download
                print("Cancelling download, file removed remotely")
                bgManager.cancelDownload(videoId: downloadedVideo.video.id)
                continue
            }
            
            let oldFilename = downloadedVideo.video.filename
            let newFilename = updatedVideo.filename
            
            if downloadedVideo.video != updatedVideo {
                print("Video has changed!")
                
                updateStatus(
                    downloadedVideo.id,
                    status: downloadedVideo.downloadStatus,
                    receivedBytes: 0,
                    totalBytes: updatedVideo.size,
                    errorMessage: nil,
                    video: updatedVideo
                )
                persist()
            }
            
            print("[DownloadsViewModel] Checking video \(downloadedVideo.id): \(oldFilename) -> \(newFilename)")
            
            let isFilenameChanged = (newFilename != oldFilename)
            let isInProgress = (downloadedVideo.downloadStatus == .downloading)
            
            if isFilenameChanged || downloadedVideo.errorMessage != nil {
                print("[DownloadsViewModel] \(downloadedVideo.id)'s URL changed. Updating size (if any) and resuming download with new URL.")
                
                guard let remoteURL = buildRemoteURL(updatedVideo) else {
                    print("[DownloadsViewModel] [ERROR] Could not build remote URL for \(downloadedVideo.id). Skipping.")
                    continue
                }
                
                if isInProgress {
                    bgManager.resumeDownload(videoId: downloadedVideo.id, from: remoteURL)
                }
            } else {
                print("[DownloadsViewModel] \(downloadedVideo.id)'s URL unchanged or not in progress. No action taken.")
            }
        }
    }
    
    /// Returns the fractional progress (0.0 -> 1.0) for a given `DownloadedVideo`.
    func progress(for item: DownloadedVideo) -> Double {
        guard item.totalBytes > 0 else { return 0.0 }
        return min(1.0, Double(item.downloadedBytes) / Double(item.totalBytes))
    }

    /// Checks if a given item has fully finished downloading.
    func isFullyDownloaded(_ item: DownloadedVideo) -> Bool {
        item.downloadStatus == .completed
    }
    
    /// Returns the `DownloadedVideo` for a given `Video` (creates a new entry if none exists).
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
    
    // MARK: - Private Helpers
    
    /// Updates the status of a specific `DownloadedVideo` in `videos`.
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
        
        print("[DownloadsViewModel] Updated status for \(videoId) => \(status). "
              + "downloadedBytes=\(v.downloadedBytes), totalBytes=\(v.totalBytes), error=\(errorMessage ?? "nil")")
        
        persist()
    }

    /// Builds the remote download URL for a given `Video`.
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
            
            updateStatus(
                videoId,
                status: .downloading,
                receivedBytes: current,
                totalBytes: total
            )
            
            print("[DownloadsViewModel] [Segmented] \(videoId) progress: \(progress * 100)%")
        }
    }
    
    func segmentedDownloadDidComplete(videoId: String, fileURL: URL) {
        Task { @MainActor in
            print("[DownloadsViewModel] [Segmented] \(videoId) => Completed, file: \(fileURL.lastPathComponent)")
            updateStatus(videoId, status: .completed)
            
            // Optionally trigger a local notification WITH the full `Video` object
            if let item = videos.first(where: { $0.id == videoId }) {
                let title = item.video.title ?? "(Untitled)"
                
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
