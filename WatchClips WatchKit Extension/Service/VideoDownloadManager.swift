//
//  VideoDownloadManager.swift
//  SingleStreamResumable
//
//  Created by Example on 2024-01-01.
//

import Foundation
import AVFoundation
import CryptoKit

/// A helper struct to track progress in a nice fraction
struct DownloadProgress {
    let receivedBytes: Int64
    let totalBytes: Int64
    
    var fraction: Double {
        guard totalBytes > 0 else { return 0.0 }
        return Double(receivedBytes) / Double(totalBytes)
    }
}

/// A single-stream (non-background) download manager that supports partial downloads (.part files),
/// pausing, and resuming from the partial offset.
class VideoDownloadManager: NSObject {
    static let shared = VideoDownloadManager()
    static let downloadStore = DownloadsStore()
    
    private override init() {}
    
    // If you want to observe progress externally, you can publish changes here:
    @Published var progressByVideoId: [String: Double] = [:]
    
    // (Optional) Keep references to tasks if needed:
    private var activeTasks: [URL: URLSessionDataTask] = [:]
    
    // For each remote URL, we store the current & total bytes.
    // This is how we track how many bytes are appended to the .part file.
    private var progressInfo: [URL: (current: Int64, total: Int64)] = [:]
    
    // For each remote URL, we store callbacks: (onProgress, onComplete)
    private var callbackForURL: [URL: ((DownloadProgress) -> Void, (Result<URL,Error>) -> Void)] = [:]
    
    // MARK: - Starting or Resuming a Download
    
    /// Called to either start from 0 or resume from any partial .part offset,
    /// using a HEAD request to confirm total file size.
    func resumeOrStartDownload(
        from remoteURL: URL,
        progressCallback: @escaping (DownloadProgress) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        print("[VideoDownloadManager] resumeOrStartDownload called for: \(remoteURL.lastPathComponent)")
        
        // 1) HEAD to find total size
        attemptHEAD(url: remoteURL, attempts: 3, delaySeconds: 2) { headResult in
            switch headResult {
            case .failure(let err):
                print("[VideoDownloadManager] [ERROR] HEAD request for \(remoteURL.lastPathComponent) failed after all attempts: \(err.localizedDescription)")
                completion(.failure(err))
                
            case .success(let totalFileSize):
                print("[VideoDownloadManager] HEAD succeeded for \(remoteURL.lastPathComponent); totalFileSize = \(totalFileSize)")
                // 2) Once HEAD has totalFileSize, do the partial-logic on main queue.
                DispatchQueue.main.async {
                    self.startSingleStream(
                        remoteURL: remoteURL,
                        totalSize: totalFileSize,
                        progressCallback: progressCallback,
                        completion: completion
                    )
                }
            }
        }
    }
    
    /// Actually performs or resumes the single-stream download from partial offset
    private func startSingleStream(
        remoteURL: URL,
        totalSize: Int64,
        progressCallback: @escaping (DownloadProgress) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        print("[VideoDownloadManager] startSingleStream called for: \(remoteURL.lastPathComponent) with totalSize=\(totalSize)")
        
        let partialURL = partialFilePath(for: remoteURL)
        let existingSize = fileSize(at: partialURL)
        
        // Build the request:
        var request = URLRequest(url: remoteURL)
        
        // If we already have a partial file, set the Range header
        if existingSize > 0 && existingSize < totalSize {
            request.setValue("bytes=\(existingSize)-", forHTTPHeaderField: "Range")
            print("[VideoDownloadManager] Resuming from byte=\(existingSize). Range: \(existingSize)-\(totalSize-1)")
        } else if existingSize >= totalSize {
            // Means we probably already downloaded it fully; check if valid or re-download
            print("[VideoDownloadManager] Found .part file >= totalSize (\(existingSize)/\(totalSize)). Validating local file...")
            DispatchQueue.main.async {
                self.validateDownloadedFile(partialURL, totalExpectedBytes: totalSize) { valid in
                    if valid {
                        print("[VideoDownloadManager] Local partial file is valid; returning success.")
                        completion(.success(partialURL))
                    } else {
                        print("[VideoDownloadManager] [ERROR] Corrupt local partial file. Removing file.")
                        try? FileManager.default.removeItem(at: partialURL)
                        completion(.failure(NSError(domain: "", code: -1, userInfo: [
                            NSLocalizedDescriptionKey: "Corrupt local file"
                        ])))
                    }
                }
            }
            return
        }
        
        // 3) Make a data task
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        let task = session.dataTask(with: request)
        task.taskDescription = remoteURL.absoluteString
        
        // 4) Store progress info & callbacks
        progressInfo[remoteURL] = (existingSize, totalSize)
        callbackForURL[remoteURL] = (progressCallback, completion)
        activeTasks[remoteURL] = task
        
        // 5) Start
        print("[VideoDownloadManager] Starting dataTask for \(remoteURL.lastPathComponent)")
        task.resume()
    }
    
    // MARK: - Pausing
    
    /// Cancels the active dataTask. Because we keep the partial .part file,
    /// we can truly resume from the offset next time we call `resumeOrStartDownload`.
    func pauseDownload(remoteURL: URL) {
        guard let task = activeTasks[remoteURL] else {
            print("[VideoDownloadManager] [WARNING] No active task to pause for \(remoteURL.lastPathComponent).")
            return
        }
        print("[VideoDownloadManager] Pausing download for \(remoteURL.lastPathComponent). Cancelling dataTask.")
        task.cancel()  // we do not remove the partial file => real resume is possible
        activeTasks.removeValue(forKey: remoteURL)
    }
    
    // MARK: - HEAD request logic
    
    private func attemptHEAD(url: URL, attempts: Int, delaySeconds: Int,
                             completion: @escaping (Result<Int64, Error>) -> Void) {
        if attempts <= 0 {
            let errorMsg = "[VideoDownloadManager] [ERROR] All HEAD attempts failed for \(url.lastPathComponent)."
            print(errorMsg)
            completion(.failure(NSError(domain: "", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "All HEAD attempts failed."
            ])))
            return
        }
        
        print("[VideoDownloadManager] Attempting HEAD for \(url.lastPathComponent). attempts left: \(attempts)")
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        
        URLSession.shared.dataTask(with: req) { _, response, error in
            if let err = error {
                print("[VideoDownloadManager] HEAD attempt failed for \(url.lastPathComponent): \(err.localizedDescription). attempts left: \(attempts - 1)")
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delaySeconds)) {
                    self.attemptHEAD(url: url, attempts: attempts - 1, delaySeconds: delaySeconds, completion: completion)
                }
                return
            }
            
            guard
                let httpResponse = response as? HTTPURLResponse,
                let contentLengthStr = httpResponse.allHeaderFields["Content-Length"] as? String,
                let fileSize = Int64(contentLengthStr),
                (200...299).contains(httpResponse.statusCode)
            else {
                print("[VideoDownloadManager] [ERROR] HEAD invalid response or missing Content-Length for \(url.lastPathComponent). attempts left: \(attempts - 1)")
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delaySeconds)) {
                    self.attemptHEAD(url: url, attempts: attempts - 1, delaySeconds: delaySeconds, completion: completion)
                }
                return
            }
            
            print("[VideoDownloadManager] HEAD success for \(url.lastPathComponent). fileSize=\(fileSize)")
            completion(.success(fileSize))
        }.resume()
    }
    
    // MARK: - Validation
    
    /// A quick check:
    /// 1) local size >= expected total
    /// 2) optionally check if the file is playable with AVAsset if you want more confidence
    private func validateDownloadedFile(_ fileURL: URL, totalExpectedBytes: Int64, completion: @escaping (Bool) -> Void) {
        let actualSize = fileSize(at: fileURL)
        if actualSize < totalExpectedBytes {
            print("[VideoDownloadManager] [ERROR] validateDownloadedFile fail: localSize < totalExpected (\(actualSize)/\(totalExpectedBytes))")
            completion(false)
            return
        }
        
        // Optional: check playable
        print("[VideoDownloadManager] Validating local file with AVAsset for \(fileURL.lastPathComponent)")
        let asset = AVURLAsset(url: fileURL)
        asset.loadValuesAsynchronously(forKeys: ["playable"]) {
            var error: NSError?
            let status = asset.statusOfValue(forKey: "playable", error: &error)
            if status == .loaded, asset.isPlayable {
                print("[VideoDownloadManager] File is playable: \(fileURL.lastPathComponent)")
                completion(true)
            } else {
                print("[VideoDownloadManager] [ERROR] File is not playable: \(fileURL.lastPathComponent)")
                completion(false)
            }
        }
    }
    
    // MARK: - File Utility
    
    private func partialFilePath(for remoteURL: URL) -> URL {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let hashed = sha256(remoteURL.absoluteString) + ".part"
        return cachesDir.appendingPathComponent(hashed)
    }
    
    private func fileSize(at url: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[VideoDownloadManager] fileSize: no file at path: \(url.lastPathComponent)")
            return 0
        }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attrs[.size] as? Int64 {
                return size
            }
        } catch {
            print("[VideoDownloadManager] [ERROR] fileSize error for \(url.lastPathComponent): \(error.localizedDescription)")
        }
        return 0
    }
    
    private func cachedFileURL(for code: String, videoId: String) -> URL {
        // e.g., unify with the approach in your code:
        let remoteURL = URL(string: "https://dwxvsu8u3eeuu.cloudfront.net/processed/\(code)/\(videoId).mp4")!
        return cachedFileURLFromRemoteURL(remoteURL)
    }
    
    private func cachedFileURLFromRemoteURL(_ remoteURL: URL) -> URL {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let hashedName = sha256(remoteURL.absoluteString) + ".mp4"
        return cachesDir.appendingPathComponent(hashedName)
    }
    
    private func sha256(_ str: String) -> String {
        let data = Data(str.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Remove all .mp4 & .part from caches
    func deleteAllSavedVideos() {
        print("[VideoDownloadManager] deleteAllSavedVideos called. Removing .mp4 and .part files...")
        
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: cachesDir, includingPropertiesForKeys: nil)
            for file in contents {
                if file.pathExtension == "mp4" || file.pathExtension == "part" {
                    try FileManager.default.removeItem(at: file)
                    print("[VideoDownloadManager] Removed \(file.lastPathComponent)")
                }
            }
        } catch {
            print("[VideoDownloadManager] [ERROR] Error removing all videos: \(error.localizedDescription)")
        }
    }
    
    /// After finishing the partial .part file, you might rename it to .mp4 once validated.
    private func finalizeDownloadFile(_ partialURL: URL, remoteURL: URL) -> URL {
        // e.g., rename from .part => .mp4 in the caches directory
        let finalURL = cachedFileURLFromRemoteURL(remoteURL)
        // remove if old final exists
        if FileManager.default.fileExists(atPath: finalURL.path) {
            do {
                try FileManager.default.removeItem(at: finalURL)
                print("[VideoDownloadManager] Removed existing file at finalURL: \(finalURL.lastPathComponent)")
            } catch {
                print("[VideoDownloadManager] [ERROR] Could not remove existing file at \(finalURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        do {
            try FileManager.default.moveItem(at: partialURL, to: finalURL)
            print("[VideoDownloadManager] Successfully moved \(partialURL.lastPathComponent) to \(finalURL.lastPathComponent)")
        } catch {
            print("[VideoDownloadManager] [ERROR] rename/move error: \(error.localizedDescription)")
        }
        return finalURL
    }
    
    /// Remove final & partial files for a single code/videoId
    func deleteVideoFor(code: String, videoId: String) {
        VideoDownloadManager.downloadStore.removeById(videoId: videoId)
        print("[VideoDownloadManager] deleteVideoFor called for code=\(code), videoId=\(videoId).")
        let finalURL = cachedFileURL(for: code, videoId: videoId)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            do {
                try FileManager.default.removeItem(at: finalURL)
                print("[VideoDownloadManager] Removed final .mp4 for \(finalURL.lastPathComponent)")
            } catch {
                print("[VideoDownloadManager] [ERROR] Could not remove final file at \(finalURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        let partialURL = partialFilePath(for: finalURL)
        if FileManager.default.fileExists(atPath: partialURL.path) {
            do {
                try FileManager.default.removeItem(at: partialURL)
                print("[VideoDownloadManager] Removed partial .part for \(partialURL.lastPathComponent)")
            } catch {
                print("[VideoDownloadManager] [ERROR] Could not remove partial file at \(partialURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
    
    func localFileURL(for code: String, videoId: String) -> URL? {
        let fileURL = cachedFileURL(for: code, videoId: videoId)
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        print("[VideoDownloadManager] Checking local file for code=\(code), videoId=\(videoId) -> exists=\(exists)")
        return exists ? fileURL : nil
    }

    /// Checks if final .mp4 is present
    func isVideoCached(code: String, videoId: String) -> Bool {
        let fileURL = cachedFileURL(for: code, videoId: videoId)
        let result = FileManager.default.fileExists(atPath: fileURL.path)
        print("[VideoDownloadManager] isVideoCached? code=\(code), videoId=\(videoId) -> \(result)")
        return result
    }
}

// MARK: - URLSessionDataDelegate (Single-Stream)

extension VideoDownloadManager: URLSessionDataDelegate {
    
    /// We append each chunk to the partial .part
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard
            let str = dataTask.taskDescription,
            let remoteURL = URL(string: str)
        else {
            print("[VideoDownloadManager] [ERROR] dataTask.taskDescription was nil or invalid. Cannot append data.")
            return
        }
        
        let partialURL = partialFilePath(for: remoteURL)
        // ensure file exists
        if !FileManager.default.fileExists(atPath: partialURL.path) {
            FileManager.default.createFile(atPath: partialURL.path, contents: nil)
            print("[VideoDownloadManager] Created partial file at \(partialURL.lastPathComponent)")
        }
        
        // Append
        do {
            let handle = try FileHandle(forWritingTo: partialURL)
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } catch {
            print("[VideoDownloadManager] [ERROR] Writing partial data failed for \(partialURL.lastPathComponent): \(error.localizedDescription)")
        }
        
        // Update memory progress
        if var (current, total) = progressInfo[remoteURL] {
            current += Int64(data.count)
            progressInfo[remoteURL] = (current, total)
            
            let prog = DownloadProgress(receivedBytes: current, totalBytes: total)
            if let (onProgress, _) = callbackForURL[remoteURL] {
                onProgress(prog)
            }
        } else {
            print("[VideoDownloadManager] [ERROR] No stored progressInfo for \(remoteURL.lastPathComponent). Can't update progress.")
        }
    }
    
    /// Called after the response is received. Accept it
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(.allow)
    }
    
    /// Called when the entire dataTask completes
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard
            let str = task.taskDescription,
            let remoteURL = URL(string: str)
        else {
            print("[VideoDownloadManager] [ERROR] didCompleteWithError called but could not map taskDescription to URL.")
            return
        }
        
        // Stop tracking the task
        activeTasks.removeValue(forKey: remoteURL)
        
        guard let (_, onComplete) = callbackForURL[remoteURL] else {
            print("[VideoDownloadManager] [ERROR] No stored completion callback for \(remoteURL.lastPathComponent).")
            return
        }
        callbackForURL[remoteURL] = nil
        
        if let err = error {
            // If user paused, or any real error
            print("[VideoDownloadManager] [ERROR] Task completed with error for \(remoteURL.lastPathComponent): \(err.localizedDescription)")
            onComplete(.failure(err))
            return
        }
        
        // No error => we've presumably got the full file in the .part
        guard let (currentBytes, total) = progressInfo[remoteURL] else {
            print("[VideoDownloadManager] [ERROR] Missing progressInfo for \(remoteURL.lastPathComponent). Cannot finalize download.")
            onComplete(.failure(NSError(domain: "", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "No progress info"
            ])))
            return
        }
        
        print("[VideoDownloadManager] Task completed successfully for \(remoteURL.lastPathComponent). Final size=\(currentBytes)/\(total)")
        
        let partialURL = partialFilePath(for: remoteURL)
        // Validate
        validateDownloadedFile(partialURL, totalExpectedBytes: total) { valid in
            if valid {
                let finalURL = self.finalizeDownloadFile(partialURL, remoteURL: remoteURL)
                onComplete(.success(finalURL))
            } else {
                // not playable => remove .part
                print("[VideoDownloadManager] [ERROR] Invalid .part file for \(remoteURL.lastPathComponent). Removing partial.")
                try? FileManager.default.removeItem(at: partialURL)
                onComplete(.failure(NSError(domain: "", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "File not playable"
                ])))
            }
        }
    }
}
