//  DownloadsViewModel.swift
//  Example
//
//  Created by Example on 2024-01-01.
//

import SwiftUI

@MainActor
class DownloadsViewModel: ObservableObject {
    @Published var videos: [DownloadedVideo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let cachedVideosService: CachedVideosService
    private let store = DownloadsStore()
    
    /// The ForegroundDownloadManager handles the actual downloads.
    private let bgManager = ForegroundDownloadManager.shared

    init(cachedVideosService: CachedVideosService) {
        self.cachedVideosService = cachedVideosService
        bgManager.delegate = self // Become the delegate
        print("[DownloadsViewModel] Initialized with CachedVideosService.")
    }

    // MARK: - Local Persistence
    
    func loadLocalDownloads() {
        print("[DownloadsViewModel] Loading locally persisted downloads from store...")
        self.videos = store.loadDownloads()
        print("[DownloadsViewModel] Loaded \(videos.count) local downloads from store.")
    }
    
    private func persist() {
        print("[DownloadsViewModel] Persisting downloads to store...")
        store.saveDownloads(videos)
        print("[DownloadsViewModel] Persist complete.")
    }

    // MARK: - Server
    
    func loadServerVideos(forCode code: String, useCache: Bool = true) async {
        isLoading = true
        defer { isLoading = false }

        print("[DownloadsViewModel] Attempting to fetch videos from server for code: \(code).")
        
        do {
            let fetched = try await cachedVideosService.fetchVideos(forCode: code, useCache: useCache)
            print("[DownloadsViewModel] Fetched \(fetched.count) videos from server.")
            
            var newList: [DownloadedVideo] = []

            // Merge server list with local
            for serverVid in fetched {
                if let localItem = videos.first(where: { $0.id == serverVid.id }) {
                    // Keep local's download status/bytes
                    let updated = DownloadedVideo(
                        video: serverVid,
                        downloadStatus: localItem.downloadStatus,
                        downloadedBytes: localItem.downloadedBytes,
                        totalBytes: localItem.totalBytes,
                        errorMessage: localItem.errorMessage
                    )
                    newList.append(updated)
                } else {
                    // Brand new => notStarted
                    newList.append(
                        DownloadedVideo(
                            video: serverVid,
                            downloadStatus: .notStarted,
                            downloadedBytes: 0,
                            totalBytes: serverVid.size ?? 0,
                            errorMessage: nil
                        )
                    )
                }
            }
            self.videos = newList
            persist()
            print("[DownloadsViewModel] Server videos loaded and merged successfully.")
        } catch {
            let msg = "Failed to load videos from server for code: \(code). Error: \(error.localizedDescription)"
            self.errorMessage = msg
            print("[DownloadsViewModel] [ERROR] \(msg)")
        }
    }

    // MARK: - Start / Resume / Pause / Delete
    
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
        
        // Switch to "downloading"
        updateStatus(item.id, status: .downloading, errorMessage: nil)
        
        // Resume or start a fresh download via the manager
        bgManager.resumeDownload(videoId: item.id, from: remoteURL)
    }
    
    func pauseDownload(_ item: DownloadedVideo) {
        print("[DownloadsViewModel] Pausing download for videoId: \(item.id).")
        bgManager.cancelDownload(videoId: item.id)
        updateStatus(item.id, status: .paused, errorMessage: nil)
    }
    
    func deleteVideo(_ item: DownloadedVideo) {
        print("[DownloadsViewModel] Deleting local file and resetting video download for \(item.id).")
        bgManager.deleteLocalFile(videoId: item.id)

        var updated = item
        updated.downloadStatus = .notStarted
        updated.downloadedBytes = 0
        updated.errorMessage = nil

        if let index = videos.firstIndex(where: { $0.id == item.id }) {
            videos[index] = updated
            print("[DownloadsViewModel] Successfully reset download status for video \(item.id).")
        } else {
            print("[DownloadsViewModel] [ERROR] Could not find video \(item.id) in current list to delete.")
        }
        persist()
    }

    /// Resume any item that was last known "downloading" (e.g. if the app was killed).
    func resumeInProgressDownloads() {
        print("[DownloadsViewModel] Attempting to resume in-progress downloads...")
        for item in videos where item.downloadStatus == .downloading {
            let hasResumeData = bgManager.hasResumeData(for: item.id)
            let isActive = bgManager.isTaskActive(videoId: item.id)
            
            if !hasResumeData && !isActive {
                // Not truly in-progress, revert to paused or error
                print("[DownloadsViewModel] No partial data or active task for \(item.id). Not restarting.")
                updateStatus(item.id, status: .paused, errorMessage: nil)
                continue
            }
            
            guard let remoteURL = buildRemoteURL(item.video) else {
                print("[DownloadsViewModel] [ERROR] Could not build remote URL for \(item.id). Skipping resume.")
                continue
            }
            // If partial data or an active task exists, you could resumeDownload again, e.g.:
            // bgManager.resumeDownload(videoId: item.id, from: remoteURL)
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
                              errorMessage: String? = nil)
    {
        guard let idx = videos.firstIndex(where: { $0.id == videoId }) else {
            print("[DownloadsViewModel] [ERROR] Unable to update status. No matching video found for videoId: \(videoId).")
            return
        }
        
        var vid = videos[idx]
        vid.downloadStatus = status
        vid.downloadedBytes = receivedBytes ?? vid.downloadedBytes
        vid.totalBytes = totalBytes ?? vid.totalBytes
        vid.errorMessage = errorMessage
        videos[idx] = vid
        
        print("[DownloadsViewModel] Updated status for \(videoId) to \(status). "
              + "downloadedBytes=\(vid.downloadedBytes), totalBytes=\(vid.totalBytes), errorMessage=\(errorMessage ?? "nil")")
        
        persist()
    }

    private func buildRemoteURL(_ v: Video) -> URL? {
        // Example base URL - adjust to your real one
        guard let base = URL(string: "https://dwxvsu8u3eeuu.cloudfront.net") else {
            print("[DownloadsViewModel] [ERROR] Invalid base URL string.")
            return nil
        }
        return base
            .appendingPathComponent("processed")
            .appendingPathComponent(v.code)
            .appendingPathComponent("\(v.id).mp4")
    }
}

// MARK: - Conform to DownloadManagerDelegate

extension DownloadsViewModel: DownloadManagerDelegate {
    /// Called when a download has updated progress.
    func downloadDidUpdateProgress(videoId: String, receivedBytes: Int64, totalBytes: Int64) {
        Task { @MainActor in
            print("[DownloadsViewModel] Progress update for \(videoId): \(receivedBytes)/\(totalBytes)")
            updateStatus(videoId, status: .downloading,
                         receivedBytes: receivedBytes,
                         totalBytes: totalBytes,
                         errorMessage: nil)
        }
    }

    /// Called when a download completes successfully.
    func downloadDidComplete(videoId: String, localFileURL: URL?) {
        Task { @MainActor in
            print("[DownloadsViewModel] Download complete for \(videoId). Local file: \(localFileURL?.lastPathComponent ?? "nil")")
            updateStatus(videoId, status: .completed)
            
            // Find the corresponding video so we can get its title
            guard let item = videos.first(where: { $0.id == videoId }) else {
                print("[DownloadsViewModel] Could not find item for videoId: \(videoId)")
                return
            }
            
            // Use the video's actual title for the notification
            let videoTitle = item.video.title ?? ""  // e.g., "My Great Video"
            
            // **Notify the user of completion** via a local notification:
            NotificationManager.shared.scheduleLocalNotification(
                title: videoTitle,
                body: "Download is complete! Your video is ready to watch."
            ) { success in
                print("[DownloadsViewModel] Notification scheduled? \(success)")
            }
        }
    }

    /// Called when a download fails with an error.
    func downloadDidFail(videoId: String, error: Error) {
        print("[DownloadsViewModel] [ERROR] Download failed for \(videoId). Error: \(error.localizedDescription)")
        Task { @MainActor in
            updateStatus(videoId, status: .error, errorMessage: error.localizedDescription)
        }
    }
}
