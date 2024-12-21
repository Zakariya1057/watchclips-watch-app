//
//  ForegroundDownloadManager.swift
//  Example
//
//  Created by Example on 2024-01-01.
//  Reverted to a straightforward foreground download without snapshotting.
//  Partial data only saved upon explicit user pause.
//

import Foundation

/// Delegate to receive progress & completion events
protocol DownloadManagerDelegate: AnyObject {
    func downloadDidUpdateProgress(videoId: String, receivedBytes: Int64, totalBytes: Int64)
    func downloadDidComplete(videoId: String, localFileURL: URL?)
    func downloadDidFail(videoId: String, error: Error)
}

/// A simplified manager for foreground downloads with optional pause & resume.
class ForegroundDownloadManager: NSObject, URLSessionDownloadDelegate {
    
    static let shared = ForegroundDownloadManager()
    private override init() {}
    
    // MARK: - Configuration
    
    /// Foreground URLSession with moderate timeouts (customize as needed).
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 100
        config.timeoutIntervalForResource = 2000
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    // MARK: - Public/Delegate
    
    weak var delegate: DownloadManagerDelegate?
    
    // MARK: - State Tracking
    
    /// Keep track of active tasks by videoId
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    
    /// Store partial resume data if a download is paused
    private var resumeDataByVideo: [String: Data] = [:]
    
    // MARK: - Public API
    
    /// Start a new download
    func startDownload(videoId: String, from url: URL) {
        print("[DownloadManager] Starting new download for \(videoId), url=\(url)")
        
        let task = urlSession.downloadTask(with: url)
        activeTasks[videoId] = task
        task.resume()
        
        print("[DownloadManager] Download task for \(videoId) is now active.")
    }
    
    /// Cancel the download (store partial data if possible)
    func cancelDownload(videoId: String) {
        guard let task = activeTasks[videoId] else {
            print("[DownloadManager] No active download to cancel for \(videoId).")
            return
        }
        task.cancel(byProducingResumeData: { [weak self] data in
            guard let self = self else { return }
            if let data = data {
                self.resumeDataByVideo[videoId] = data
                print("[DownloadManager] Paused download for \(videoId), resume data saved.")
            } else {
                print("[DownloadManager] Download \(videoId) canceled, no resume data provided.")
            }
            self.activeTasks.removeValue(forKey: videoId)
        })
    }
    
    /// Resume a paused download if we have partial data; otherwise starts fresh.
    func resumeDownload(videoId: String, from url: URL) {
        if let data = resumeDataByVideo[videoId] {
            print("[DownloadManager] Resuming \(videoId) from saved resume data.")
            let task = urlSession.downloadTask(withResumeData: data)
            resumeDataByVideo.removeValue(forKey: videoId)
            activeTasks[videoId] = task
            task.resume()
        } else {
            print("[DownloadManager] No resume data for \(videoId), starting fresh.")
            startDownload(videoId: videoId, from: url)
        }
    }
    
    /// Indicates if we have resume data in memory for a given videoId
    func hasResumeData(for videoId: String) -> Bool {
        return (resumeDataByVideo[videoId] != nil)
    }
    
    /// Indicates if there is an active task for a given videoId
    func isTaskActive(videoId: String) -> Bool {
        return (activeTasks[videoId] != nil)
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64)
    {
        guard let videoId = findVideoId(task: downloadTask) else { return }
        
        let total = (totalBytesExpectedToWrite > 0) ? totalBytesExpectedToWrite : 1
        let progress = Double(totalBytesWritten) / Double(total) * 100
        
        print("[DownloadManager] Progress for \(videoId): \(Int(progress))% (\(totalBytesWritten)/\(total))")
        
        delegate?.downloadDidUpdateProgress(
            videoId: videoId,
            receivedBytes: totalBytesWritten,
            totalBytes: total
        )
    }
    
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL)
    {
        guard let videoId = findVideoId(task: downloadTask) else {
            print("[DownloadManager] [ERROR] didFinishDownloadingTo - no matching videoId found.")
            return
        }
        
        // Move from temp location to caches
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let finalURL = cachesDir.appendingPathComponent("\(videoId).mp4")
        
        do {
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: location, to: finalURL)
            
            print("[DownloadManager] Moved file to \(finalURL) for \(videoId).")
            delegate?.downloadDidComplete(videoId: videoId, localFileURL: finalURL)
        } catch {
            print("[DownloadManager] [ERROR] Could not move temp file for \(videoId): \(error)")
            delegate?.downloadDidFail(videoId: videoId, error: error)
        }
        
        activeTasks.removeValue(forKey: videoId)
    }
    
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?)
    {
        guard let videoId = findVideoId(task: task) else { return }
        
        if let e = error as NSError? {
            if e.code == NSURLErrorCancelled {
                print("[DownloadManager] \(videoId) canceled or paused.")
            } else {
                print("[DownloadManager] [ERROR] \(videoId) failed: \(e.localizedDescription)")
                delegate?.downloadDidFail(videoId: videoId, error: e)
            }
        }
        
        // Clean up any leftover mapping
        activeTasks.removeValue(forKey: videoId)
    }
    
    // MARK: - Helper
    
    private func findVideoId(task: URLSessionTask) -> String? {
        return activeTasks.first { $0.value == task }?.key
    }
}

// MARK: - Additional Helpers

extension ForegroundDownloadManager {
    
    /// Where final .mp4 is stored
    func localFileURL(videoId: String) -> URL {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesDir.appendingPathComponent("\(videoId).mp4")
    }
    
    func doesLocalFileExist(videoId: String) -> Bool {
        let url = localFileURL(videoId: videoId)
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    func deleteLocalFile(videoId: String) {
        let url = localFileURL(videoId: videoId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[DownloadManager] No local file to delete for \(videoId).")
            return
        }
        
        do {
            try FileManager.default.removeItem(at: url)
            print("[DownloadManager] Deleted local file for \(videoId).")
        } catch {
            print("[DownloadManager] [ERROR] Deleting local file for \(videoId): \(error.localizedDescription)")
        }
    }
}
