//
//  ForegroundDownloadManager.swift
//  Example
//
//  Enhanced to handle partial resume across app reboots,
//  now also auto-pausing and resuming every 50MB.
//

import Foundation
import UIKit

struct DownloadMetadata: Codable {
    let videoId: String
    let remoteURL: String
}

protocol DownloadManagerDelegate: AnyObject {
    func downloadDidUpdateProgress(videoId: String, receivedBytes: Int64, totalBytes: Int64)
    func downloadDidComplete(videoId: String, localFileURL: URL?)
    func downloadDidFail(videoId: String, error: Error)
}

class ForegroundDownloadManager: NSObject, URLSessionDownloadDelegate {
    
    static let shared = ForegroundDownloadManager()
    private override init() {
        super.init()
        // On init, reload any partial tasks if you want to resume automatically
        self.reloadIncompleteDownloads()
    }
    
    // MARK: - Configuration
    
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 100
        config.timeoutIntervalForResource = 4000
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    weak var delegate: DownloadManagerDelegate?
    
    // MARK: - State Tracking
    
    /// Currently active download tasks keyed by videoId.
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    
    /// Resume data stored in memory, keyed by videoId.
    private var resumeDataByVideo: [String: Data] = [:]
    
    /// Stores which downloads are in progress across app launches.
    private var metadataList: [String: DownloadMetadata] = [:] {
        didSet { saveMetadataListToDisk() }
    }
    
    // -----------------------------------
    // AUTO-PAUSE/RESUME CHUNKING SUPPORT
    // -----------------------------------
    
    /// We pause & resume every 50 MB (50,000,000 bytes) to demonstrate partial chunk downloads.
    private let chunkSize: Int64 = 50_000_000  // 50 MB
    
    /// Track how many bytes were downloaded last time we paused for each videoId.
    private var lastPausedOffsetByVideo: [String: Int64] = [:]

    // MARK: - Public API (Signatures Unchanged)
    
    func startDownload(videoId: String, from url: URL) {
        let videoURL = url.absoluteString
        print("[DownloadManager] Starting new download for \(videoId), url=\(videoURL)")
        
        // Save metadata so we remember across reboots
        let meta = DownloadMetadata(videoId: videoId, remoteURL: videoURL)
        metadataList[videoId] = meta
        
        let task = urlSession.downloadTask(with: url)
        activeTasks[videoId] = task
        // Initialize the paused offset to 0 if we’re starting fresh
        lastPausedOffsetByVideo[videoId] = 0
        
        task.resume()
    }
    
    func cancelDownload(videoId: String) {
        guard let task = activeTasks[videoId] else {
            print("[DownloadManager] No active download to cancel for \(videoId).")
            return
        }
        
        task.cancel(byProducingResumeData: { [weak self] data in
            guard let self = self else { return }
            if let data = data {
                self.resumeDataByVideo[videoId] = data
                self.saveResumeDataToDisk(data, for: videoId)
                print("[DownloadManager] Paused download for \(videoId), resume data saved.")
            } else {
                print("[DownloadManager] Download \(videoId) canceled, no resume data provided.")
            }
            self.activeTasks.removeValue(forKey: videoId)
        })
    }
    
    func resumeDownload(videoId: String, from url: URL) {
        // 1) Check in-memory
        if let data = resumeDataByVideo[videoId] {
            print("[DownloadManager] Resuming \(videoId) from saved resume data (memory).")
            let task = urlSession.downloadTask(withResumeData: data)
            resumeDataByVideo.removeValue(forKey: videoId)
            removeResumeDataFromDisk(for: videoId)
            activeTasks[videoId] = task
            task.resume()
            return
        }
        
        // 2) Check disk
        if let diskData = loadResumeDataFromDisk(for: videoId) {
            print("[DownloadManager] Resuming \(videoId) from saved resume data (disk).")
            let task = urlSession.downloadTask(withResumeData: diskData)
            removeResumeDataFromDisk(for: videoId)
            activeTasks[videoId] = task
            task.resume()
            return
        }
        
        // 3) Start fresh if no resume data
        print("[DownloadManager] No resume data for \(videoId), starting fresh.")
        startDownload(videoId: videoId, from: url)
    }
    
    func hasResumeData(for videoId: String) -> Bool {
        // memory check
        if resumeDataByVideo[videoId] != nil { return true }
        // disk check
        let resumePath = resumeDataURL(for: videoId).path
        return FileManager.default.fileExists(atPath: resumePath)
    }
    
    func isTaskActive(videoId: String) -> Bool {
        return activeTasks[videoId] != nil
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        
        guard let videoId = findVideoId(task: downloadTask) else { return }
        
        let totalExpected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 1
        let progress = Double(totalBytesWritten) / Double(totalExpected) * 100
        print("[DownloadManager] Progress for \(videoId): \(Int(progress))% (\(totalBytesWritten)/\(totalExpected))")
        
        // Notify delegate about progress
        delegate?.downloadDidUpdateProgress(videoId: videoId,
                                            receivedBytes: totalBytesWritten,
                                            totalBytes: totalExpected)
        
        //-----------------------------------------
        // AUTOMATIC PAUSE & RESUME EVERY 50MB
        //-----------------------------------------
        let lastPausedOffset = lastPausedOffsetByVideo[videoId] ?? 0
        if (totalBytesWritten - lastPausedOffset) >= chunkSize {
            // We’ve downloaded another 50 MB chunk; auto-pause and then resume.
            print("[DownloadManager] Auto-pausing \(videoId) after ~50MB chunk...")
            
            // Step 1: Cancel to produce resume data
            downloadTask.cancel(byProducingResumeData: { [weak self] data in
                guard let self = self else { return }
                
                // Step 2: Save that resume data
                if let data = data {
                    self.resumeDataByVideo[videoId] = data
                    self.saveResumeDataToDisk(data, for: videoId)
                    print("[DownloadManager] Auto-pause complete, saved partial data for \(videoId).")
                }
                
                // Step 3: Remove from active tasks
                self.activeTasks.removeValue(forKey: videoId)
                
                // Step 4: Update the last-paused offset to current total
                self.lastPausedOffsetByVideo[videoId] = totalBytesWritten
                
                // Step 5: Immediately resume
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                    // We have the original URL stored in metadataList
                    if let meta = self.metadataList[videoId],
                       let remoteURL = URL(string: meta.remoteURL) {
                        print("[DownloadManager] Auto-resuming \(videoId) from last chunk.")
                        self.resumeDownload(videoId: videoId, from: remoteURL)
                    }
                }
            })
        }
    }
    
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let videoId = findVideoId(task: downloadTask) else {
            print("[DownloadManager] [ERROR] didFinishDownloadingTo - no matching videoId found.")
            return
        }
        
        // Move to final location
        let finalURL = localFileURL(videoId: videoId)
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
        
        // Cleanup
        activeTasks.removeValue(forKey: videoId)
        removeResumeDataFromDisk(for: videoId)
        resumeDataByVideo.removeValue(forKey: videoId)
        metadataList.removeValue(forKey: videoId)
        
        // Also clear any lastPausedOffset so future downloads start fresh
        lastPausedOffsetByVideo.removeValue(forKey: videoId)
    }
    
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let videoId = findVideoId(task: task) else { return }
        
        if let e = error as NSError? {
            // If canceled or paused, we handle in the cancel code above
            if e.code == NSURLErrorCancelled {
                print("[DownloadManager] \(videoId) canceled or paused (no further action).")
            } else {
                // Another type of failure
                print("[DownloadManager] [ERROR] \(videoId) failed: \(e.localizedDescription)")
                (task as? URLSessionDownloadTask)?.cancel(byProducingResumeData: { [weak self] data in
                    guard let self = self else { return }
                    if let data = data {
                        self.resumeDataByVideo[videoId] = data
                        self.saveResumeDataToDisk(data, for: videoId)
                        print("[DownloadManager] Saved partial data for \(videoId).")
                    } else {
                        print("[DownloadManager] No partial data available for \(videoId).")
                    }
                    self.delegate?.downloadDidFail(videoId: videoId, error: e)
                    self.activeTasks.removeValue(forKey: videoId)
                })
                return
            }
        }
        
        // If no error or canceled, remove from active tasks
        activeTasks.removeValue(forKey: videoId)
    }
    
    // MARK: - Internal Helpers
    
    private func findVideoId(task: URLSessionTask) -> String? {
        return activeTasks.first { $0.value == task }?.key
    }
    
    func localFileURL(videoId: String) -> URL {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesDir.appendingPathComponent("\(videoId).mp4")
    }
    
    func doesLocalFileExist(videoId: String) -> Bool {
        return FileManager.default.fileExists(atPath: localFileURL(videoId: videoId).path)
    }
    
    func deleteLocalFile(videoId: String) {
        let url = localFileURL(videoId: videoId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
            print("[DownloadManager] Deleted local file for \(videoId).")
        } catch {
            print("[DownloadManager] [ERROR] Deleting file for \(videoId): \(error)")
        }
    }
    
    // MARK: - Resume Data Persistence
    
    private func resumeDataURL(for videoId: String) -> URL {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let resumeDir = cachesDir.appendingPathComponent("ResumeData", isDirectory: true)
        if !FileManager.default.fileExists(atPath: resumeDir.path) {
            do {
                try FileManager.default.createDirectory(at: resumeDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("[DownloadManager] [ERROR] Could not create ResumeData directory: \(error)")
            }
        }
        return resumeDir.appendingPathComponent("\(videoId).resume")
    }
    
    private func saveResumeDataToDisk(_ data: Data, for videoId: String) {
        let url = resumeDataURL(for: videoId)
        DispatchQueue.global(qos: .background).async {
            do {
                try data.write(to: url, options: .atomic)
                print("[DownloadManager] Resume data written to disk for \(videoId).")
            } catch {
                print("[DownloadManager] [ERROR] Writing resume data for \(videoId): \(error)")
            }
        }
    }
    
    private func loadResumeDataFromDisk(for videoId: String) -> Data? {
        let url = resumeDataURL(for: videoId)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            print("[DownloadManager] Loaded resume data from disk for \(videoId).")
            return data
        } catch {
            print("[DownloadManager] [ERROR] Reading resume data for \(videoId): \(error)")
            return nil
        }
    }
    
    private func removeResumeDataFromDisk(for videoId: String) {
        let url = resumeDataURL(for: videoId)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
            print("[DownloadManager] Removed resume data file for \(videoId).")
        } catch {
            print("[DownloadManager] [ERROR] Removing resume data for \(videoId): \(error)")
        }
    }
    
    // MARK: - Metadata Persistence
    
    private func metadataListURL() -> URL {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesDir.appendingPathComponent("DownloadsManifest.json")
    }
    
    private func saveMetadataListToDisk() {
        do {
            let data = try JSONEncoder().encode(Array(metadataList.values))
            try data.write(to: metadataListURL(), options: .atomic)
        } catch {
            print("[DownloadManager] [ERROR] Saving metadataList: \(error)")
        }
    }
    
    private func loadMetadataListFromDisk() -> [String: DownloadMetadata] {
        let url = metadataListURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            let data = try Data(contentsOf: url)
            let items = try JSONDecoder().decode([DownloadMetadata].self, from: data)
            var dict = [String: DownloadMetadata]()
            for meta in items {
                dict[meta.videoId] = meta
            }
            return dict
        } catch {
            print("[DownloadManager] [ERROR] Loading metadataList: \(error)")
            return [:]
        }
    }
    
    private func reloadIncompleteDownloads() {
        // Load from disk
        let loaded = loadMetadataListFromDisk()
        self.metadataList = loaded
        
        // If you want to automatically resume on startup, you can do so here:
        /*
        for (videoId, meta) in loaded {
            if hasResumeData(for: videoId) {
                let url = URL(string: meta.remoteURL)!
                resumeDownload(videoId: videoId, from: url)
            } else {
                // or start fresh, depending on app logic
                // startDownload(videoId: videoId, from: url)
            }
        }
        */
    }
}
