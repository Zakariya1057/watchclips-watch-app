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

@MainActor
class DownloadsViewModel: ObservableObject {
    // MARK: - Published Properties

    @EnvironmentObject var sharedVM: SharedVideosViewModel
    
    @Published var videos: [DownloadedVideo] = []
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let cachedVideosService: CachedVideosService
    private let store = DownloadsStore()
    
    /// Parallel chunk-based manager (with two-host splitting).
    private let bgManager = SegmentedDownloadManager.shared

    // MARK: - Init

    init(cachedVideosService: CachedVideosService) {
        self.cachedVideosService = cachedVideosService
        
        // Become the chunk-based delegate
        bgManager.segmentedDelegate = self
        
        // (Optional) Also handle old-style callbacks:
        bgManager.oldDelegate = self
        
        print("[DownloadsViewModel] Initialized with CachedVideosService.")
        
        // Load previously saved downloads on initialization:
        loadLocalDownloads()
    }
    
    // MARK: - Local Persistence
    
    func setVideos(newVideos: [Video]) {
        let downloadedVideo = store.loadDownloads()
        
        self.videos = newVideos.map { video in
            // If we already have a matching entry for this video, reuse its data
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
                    lastDownloadURL: nil
                )
            }
        }
    }
    
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
            self.updateStatus(item.id, status: .downloading, errorMessage: nil)
            
            // Let the chunk-based manager do the rest
            // 'resumeDownload' will handle partial data if it exists
            self.bgManager.resumeDownload(videoId: item.id, from: remoteURL)
        }
    }
    
    func pauseDownload(_ item: DownloadedVideo) {
        print("[DownloadsViewModel] Pausing download for \(item.id).")
        
        Task {
            self.bgManager.cancelDownload(videoId: item.id)
            self.updateStatus(item.id, status: .paused, errorMessage: nil)
        }
    }
    
    /// Deletes both the final `.mp4` and any partial data if the download is in progress.
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
    
    // MARK: - Resume in-progress downloads

    func resumeInProgressDownloads() {
        print("[DownloadsViewModel] Attempting to resume in-progress downloads (chunk-based).")
        
        for item in videos where item.downloadStatus == .downloading {
            // Check if the manager believes there's an active task for this video.
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
    
    // MARK: - onAppearCheckForURLChanges
    
    /// Call this from a SwiftUI View's `onAppear` to ensure each video's URL is up-to-date.
    /// If the URL has changed, call `startDownload(...)`.
    /// If it's unchanged, do nothing.
    func onAppearCheckForURLChanges() {
        print("[DownloadsViewModel] onAppear => Checking for any changed URLs in all videos.")
        
        for (index, item) in videos.enumerated() {
            // Build the current/expected remote URL
            guard let remoteURL = buildRemoteURL(item.video) else {
                print("[DownloadsViewModel] [ERROR] Could not build remote URL for \(item.id). Skipping check.")
                continue
            }
            
            // If the URL changed (or was never set), let's force a (re)startDownload
            if item.lastDownloadURL != remoteURL, item.downloadedBytes > 0, item.downloadStatus == .downloading {
                print("[DownloadsViewModel] \(item.id)'s URL changed (or nil). Calling startDownload.")
                
                bgManager.resumeDownload(videoId: item.id, from: remoteURL)
                
                // Update lastDownloadURL in our local array
                videos[index].lastDownloadURL = remoteURL
                persist()
            } else {
                print("[DownloadsViewModel] \(item.id)'s URL has not changed. Doing nothing.")
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
            
            updateStatus(videoId,
                         status: .downloading,
                         receivedBytes: current,
                         totalBytes: total)
            
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
            updateStatus(videoId,
                         status: .downloading,
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

// MARK: - itemFor(video:)
extension DownloadsViewModel {
    /// Return the `DownloadedVideo` item for a given `Video`, or create one if it doesn't exist in our local array.
    func itemFor(video: Video) -> DownloadedVideo {
        if let existing = videos.first(where: { $0.video.id == video.id }) {
            // Return the existing item (keeping status, bytes, etc.)
            return existing
        } else {
            let newDownload = DownloadedVideo(
                video: video,
                downloadStatus: .notStarted,
                downloadedBytes: 0,
                totalBytes: video.size ?? 0,
                errorMessage: nil,
                lastDownloadURL: nil
            )
            
            // Append it safely on the main thread
            DispatchQueue.main.async {
                self.videos.append(newDownload)
            }
            
            return newDownload
        }
    }
}
