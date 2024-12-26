//import Foundation
//import WatchKit
//
//// MARK: - Models & Protocol
//
//struct DownloadMetadata: Codable {
//    let videoId: String
//    let remoteURL: String
//}
//
//protocol DownloadManagerDelegate: AnyObject {
//    func downloadDidUpdateProgress(videoId: String, receivedBytes: Int64, totalBytes: Int64)
//    func downloadDidComplete(videoId: String, localFileURL: URL?)
//    func downloadDidFail(videoId: String, error: Error)
//}
//
//// MARK: - Segmented Download Context
//
///// Holds state for a single segmented download operation.
//private class SegmentedDownloadContext {
//    let videoId: String
//    let remoteURL: URL
//    let totalSize: Int64
//    let segmentSize: Int64
//    
//    /// Which chunk we are currently fetching.
//    var currentSegmentIndex: Int = 0
//    
//    /// Retry counts per chunk index.
//    var segmentRetryCount: [Int: Int] = [:]
//    
//    init(videoId: String, remoteURL: URL, totalSize: Int64, segmentSize: Int64) {
//        self.videoId = videoId
//        self.remoteURL = remoteURL
//        self.totalSize = totalSize
//        self.segmentSize = segmentSize
//        
//        // Initialize retry counts to 0 for each chunk
//        for i in 0..<totalSegments {
//            segmentRetryCount[i] = 0
//        }
//    }
//    
//    /// How many chunks in total.
//    var totalSegments: Int {
//        return Int((totalSize + (segmentSize - 1)) / segmentSize)
//    }
//}
//
//// MARK: - ForegroundDownloadManager (Segmented Version)
//
//class ForegroundDownloadManager: NSObject {
//    
//    static let shared = ForegroundDownloadManager()
//    private override init() {
//        super.init()
//        self.reloadIncompleteDownloads()
//    }
//    
//    // MARK: - Configuration
//    
//    /// We'll use a plain URLSession without a download delegate; we’ll use data tasks for range requests.
//    private lazy var urlSession: URLSession = {
//        let config = URLSessionConfiguration.default
//        config.timeoutIntervalForRequest = 200
//        config.allowsExpensiveNetworkAccess = true
//        // For watchOS, keep discretionary=false unless you really want system scheduling, etc.
//        return URLSession(configuration: config, delegate: nil, delegateQueue: nil)
//    }()
//    
//    weak var delegate: DownloadManagerDelegate?
//    
//    // MARK: - Manager State
//
//    /// Because we’re now using segmented downloads, we won’t track `URLSessionDownloadTask`s in `activeTasks`.
//    /// Instead, we track the custom context (chunks, retries, etc.).
//    private var activeDownloads: [String: SegmentedDownloadContext] = [:]
//    
//    /// Keep track of partial resume data (no longer used in chunk approach, but we leave it for reference).
//    private var resumeDataByVideo: [String: Data] = [:]
//    
//    /// Keep track of downloads across launches.
//    private var metadataList: [String: DownloadMetadata] = [:] {
//        didSet { saveMetadataListToDisk() }
//    }
//    
//    // MARK: - Retry Config
//
//    private let maxRetries = 10
//    private let retryDelay: TimeInterval = 5.0
//    
//    // MARK: - Chunk Size
//    
//    /// Adjust as needed. 10 MB is just an example.
//    private let chunkSize: Int64 = 1_000_000
//    
//    // MARK: - Public API
//    
//    /// Instead of using `URLSessionDownloadTask`, we do a HEAD request + segmented download.
//    func startDownload(videoId: String, from url: URL) {
//        print("[DownloadManager] Starting segmented download for \(videoId), url=\(url)")
//        
//        // Save metadata
//        let meta = DownloadMetadata(videoId: videoId, remoteURL: url.absoluteString)
//        metadataList[videoId] = meta
//        
//        // HEAD request to discover total file size
//        var headRequest = URLRequest(url: url)
//        headRequest.httpMethod = "HEAD"
//        
//        let headTask = urlSession.dataTask(with: headRequest) { [weak self] (_, response, error) in
//            guard let self = self else { return }
//            
//            if let error = error {
//                print("[DownloadManager] [ERROR] HEAD request failed: \(error)")
//                self.delegate?.downloadDidFail(videoId: videoId, error: error)
//                return
//            }
//            
//            guard let httpResponse = response as? HTTPURLResponse,
//                  httpResponse.statusCode == 200 || httpResponse.statusCode == 206 else {
//                let err = NSError(domain: "SegmentedDownload",
//                                  code: 1,
//                                  userInfo: [NSLocalizedDescriptionKey: "Invalid status on HEAD request"])
//                self.delegate?.downloadDidFail(videoId: videoId, error: err)
//                return
//            }
//            
//            // Attempt to read Content-Length
//            let lengthStr = httpResponse.allHeaderFields["Content-Length"] as? String ?? "0"
//            guard let totalSize = Int64(lengthStr) else {
//                let err = NSError(domain: "SegmentedDownload",
//                                  code: 2,
//                                  userInfo: [NSLocalizedDescriptionKey: "Unable to parse Content-Length"])
//                self.delegate?.downloadDidFail(videoId: videoId, error: err)
//                return
//            }
//            
//            // Create context for segmented download
//            let context = SegmentedDownloadContext(
//                videoId: videoId,
//                remoteURL: url,
//                totalSize: totalSize,
//                segmentSize: self.chunkSize
//            )
//            self.activeDownloads[videoId] = context
//            print("[DownloadManager] \(videoId) total size: \(totalSize) bytes, beginning chunked download...")
//            
//            // Begin by downloading the first segment
//            self.downloadNextSegment(context: context)
//        }
//        
//        headTask.resume()
//    }
//    
//    /// Cancel the segmented download by removing the context from activeDownloads.
//    func cancelDownload(videoId: String) {
//        if let _ = activeDownloads[videoId] {
//            activeDownloads.removeValue(forKey: videoId)
//            print("[DownloadManager] Canceled segmented download for \(videoId).")
//        } else {
//            print("[DownloadManager] No active segmented download to cancel for \(videoId).")
//        }
//    }
//    
//    /// NOT USED in chunk approach (but we leave it to keep your public API unchanged).
//    func resumeDownload(videoId: String, from url: URL) {
//        print("[DownloadManager] (Segmented) resumeDownload is not applicable for chunk-based approach.")
//        // No-op or re-start the entire segmented approach if needed
//        startDownload(videoId: videoId, from: url)
//    }
//    
//    /// Check if there's an active segmented context for that videoId
//    func isTaskActive(videoId: String) -> Bool {
//        return activeDownloads[videoId] != nil
//    }
//    
//    // MARK: - Chunked Download Flow
//    
//    private func downloadNextSegment(context: SegmentedDownloadContext) {
//        // If user canceled, context is gone
//        guard activeDownloads[context.videoId] != nil else { return }
//        
//        // Check if we’ve downloaded all segments
//        if context.currentSegmentIndex >= context.totalSegments {
//            // All segments done, concatenate
//            concatenateSegments(context: context)
//            return
//        }
//        
//        // Calculate range for this chunk
//        let startByte = context.segmentSize * Int64(context.currentSegmentIndex)
//        let endByte   = min(startByte + context.segmentSize - 1, context.totalSize - 1)
//        
//        var request = URLRequest(url: context.remoteURL)
//        request.httpMethod = "GET"
//        request.setValue("bytes=\(startByte)-\(endByte)", forHTTPHeaderField: "Range")
//        
//        let segmentIndex = context.currentSegmentIndex
//        print("[DownloadManager] \(context.videoId) downloading segment #\(segmentIndex) range=\(startByte)-\(endByte)")
//        
//        let dataTask = urlSession.dataTask(with: request) { [weak self] data, response, error in
//            guard let self = self else { return }
//            
//            // If canceled, bail out
//            guard self.activeDownloads[context.videoId] != nil else { return }
//            
//            if let error = error {
//                print("[DownloadManager] [ERROR] segment #\(segmentIndex) for \(context.videoId) failed: \(error)")
//                
//                // Retry logic
//                let attempts = context.segmentRetryCount[segmentIndex] ?? 0
//                if attempts < self.maxRetries {
//                    context.segmentRetryCount[segmentIndex] = attempts + 1
//                    print("[DownloadManager] Retrying segment #\(segmentIndex) in \(self.retryDelay) seconds (attempt \(attempts + 1))...")
//                    DispatchQueue.main.asyncAfter(deadline: .now() + self.retryDelay) {
//                        self.downloadNextSegment(context: context)
//                    }
//                } else {
//                    // Too many retries
//                    self.failDownload(context: context, error: error)
//                }
//                return
//            }
//            
//            // Validate response & data
//            guard let httpResponse = response as? HTTPURLResponse,
//                  (httpResponse.statusCode == 206 || httpResponse.statusCode == 200),
//                  let data = data, !data.isEmpty
//            else {
//                let err = NSError(domain: "SegmentedDownload",
//                                  code: 3,
//                                  userInfo: [NSLocalizedDescriptionKey: "Invalid response or empty data for segment #\(segmentIndex)."])
//                // Retry or fail
//                let attempts = context.segmentRetryCount[segmentIndex] ?? 0
//                if attempts < self.maxRetries {
//                    context.segmentRetryCount[segmentIndex] = attempts + 1
//                    print("[DownloadManager] Retrying segment #\(segmentIndex) (attempt \(attempts + 1))...")
//                    self.downloadNextSegment(context: context)
//                } else {
//                    self.failDownload(context: context, error: err)
//                }
//                return
//            }
//            
//            // Write segment to disk
//            do {
//                let segmentURL = self.tempSegmentURL(videoId: context.videoId, index: segmentIndex)
//                try data.write(to: segmentURL, options: .atomic)
//                print("[DownloadManager] \(context.videoId) wrote segment #\(segmentIndex) to \(segmentURL.lastPathComponent)")
//            } catch {
//                print("[DownloadManager] [ERROR] writing segment #\(segmentIndex) to disk: \(error)")
//                self.failDownload(context: context, error: error)
//                return
//            }
//            
//            // Move to next segment
//            context.currentSegmentIndex += 1
//            
//            // Update progress to delegate
//            let receivedSoFar = min(Int64(context.currentSegmentIndex) * context.segmentSize, context.totalSize)
//            self.delegate?.downloadDidUpdateProgress(
//                videoId: context.videoId,
//                receivedBytes: receivedSoFar,
//                totalBytes: context.totalSize
//            )
//            
//            // Continue with next chunk
//            self.downloadNextSegment(context: context)
//        }
//        
//        dataTask.resume()
//    }
//    
//    private func concatenateSegments(context: SegmentedDownloadContext) {
//        print("[DownloadManager] \(context.videoId) all segments downloaded, concatenating...")
//        
//        let finalURL = localFileURL(videoId: context.videoId)
//        // Remove old file if exists
//        if FileManager.default.fileExists(atPath: finalURL.path) {
//            try? FileManager.default.removeItem(at: finalURL)
//        }
//        // Create empty file
//        FileManager.default.createFile(atPath: finalURL.path, contents: nil, attributes: nil)
//        
//        guard let handle = try? FileHandle(forWritingTo: finalURL) else {
//            let err = NSError(domain: "SegmentedDownload",
//                              code: 4,
//                              userInfo: [NSLocalizedDescriptionKey: "Could not open final file handle."])
//            failDownload(context: context, error: err)
//            return
//        }
//        
//        // Append each segment
//        for i in 0..<context.totalSegments {
//            let segmentURL = tempSegmentURL(videoId: context.videoId, index: i)
//            if !FileManager.default.fileExists(atPath: segmentURL.path) {
//                let err = NSError(domain: "SegmentedDownload",
//                                  code: 5,
//                                  userInfo: [NSLocalizedDescriptionKey: "Missing segment #\(i)"])
//                failDownload(context: context, error: err)
//                handle.closeFile()
//                return
//            }
//            do {
//                let chunkData = try Data(contentsOf: segmentURL)
//                handle.seekToEndOfFile()
//                handle.write(chunkData)
//            } catch {
//                failDownload(context: context, error: error)
//                handle.closeFile()
//                return
//            }
//        }
//        
//        handle.closeFile()
//        
//        // Clean up temp segment files
//        for i in 0..<context.totalSegments {
//            let segURL = tempSegmentURL(videoId: context.videoId, index: i)
//            try? FileManager.default.removeItem(at: segURL)
//        }
//        
//        // Mark as done
//        activeDownloads.removeValue(forKey: context.videoId)
//        metadataList.removeValue(forKey: context.videoId)
//        
//        // Notify delegate
//        delegate?.downloadDidComplete(videoId: context.videoId, localFileURL: finalURL)
//    }
//    
//    private func failDownload(context: SegmentedDownloadContext, error: Error) {
//        // Remove temp files
//        for i in 0..<context.totalSegments {
//            let segURL = tempSegmentURL(videoId: context.videoId, index: i)
//            try? FileManager.default.removeItem(at: segURL)
//        }
//        // Remove from active
//        activeDownloads.removeValue(forKey: context.videoId)
//        metadataList.removeValue(forKey: context.videoId)
//        
//        // Notify
//        delegate?.downloadDidFail(videoId: context.videoId, error: error)
//    }
//    
//    // MARK: - File Helpers
//    
//    func localFileURL(videoId: String) -> URL {
//        // Reuse your existing approach
//        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
//        return cachesDir.appendingPathComponent("\(videoId).mp4")
//    }
//    
//    private func tempSegmentURL(videoId: String, index: Int) -> URL {
//        // e.g. /tmp/videoId_part0.tmp
//        let tmpDir = FileManager.default.temporaryDirectory
//        return tmpDir.appendingPathComponent("\(videoId)_part\(index).tmp")
//    }
//    
//    // MARK: - Unused Old Resume Logic
//    
//    /// We keep these around to avoid breaking your interface,
//    /// but they're not used in the segmented approach.
//    func hasResumeData(for videoId: String) -> Bool {
//        return false
//    }
//    
//    // MARK: - Old Remove/Save Resume Data
//    
//    private func saveResumeDataToDisk(_ data: Data, for videoId: String) {
//        // In chunk approach, not used
//    }
//    
//    private func removeResumeDataFromDisk(for videoId: String) {
//        // In chunk approach, not used
//    }
//    
//    private func loadResumeDataFromDisk(for videoId: String) -> Data? {
//        return nil
//    }
//    
//    // MARK: - Metadata Persistence
//    
//    private func metadataListURL() -> URL {
//        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
//        return cachesDir.appendingPathComponent("DownloadsManifest.json")
//    }
//    
//    private func saveMetadataListToDisk() {
//        do {
//            let data = try JSONEncoder().encode(Array(metadataList.values))
//            try data.write(to: metadataListURL(), options: .atomic)
//        } catch {
//            print("[DownloadManager] [ERROR] Saving metadataList: \(error)")
//        }
//    }
//    
//    private func loadMetadataListFromDisk() -> [String: DownloadMetadata] {
//        let url = metadataListURL()
//        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
//        
//        do {
//            let data = try Data(contentsOf: url)
//            let items = try JSONDecoder().decode([DownloadMetadata].self, from: data)
//            var dict = [String: DownloadMetadata]()
//            for meta in items {
//                dict[meta.videoId] = meta
//            }
//            return dict
//        } catch {
//            print("[DownloadManager] [ERROR] Loading metadataList: \(error)")
//            return [:]
//        }
//    }
//    
//    private func reloadIncompleteDownloads() {
//        let loaded = loadMetadataListFromDisk()
//        self.metadataList = loaded
//        // If you want to automatically resume on startup, do so here—but in chunk approach, you’d just re-start them.
//    }
//    
//    // MARK: - Debug Helpers
//    
//    /// You had a helper to see if local file exists
//    func doesLocalFileExist(videoId: String) -> Bool {
//        return FileManager.default.fileExists(atPath: localFileURL(videoId: videoId).path)
//    }
//    
//    /// Deletion helper
//    func deleteLocalFile(videoId: String) {
//        let path = localFileURL(videoId: videoId)
//        guard FileManager.default.fileExists(atPath: path.path) else { return }
//        do {
//            try FileManager.default.removeItem(at: path)
//            print("[DownloadManager] Deleted local file for \(videoId).")
//        } catch {
//            print("[DownloadManager] [ERROR] Deleting file for \(videoId): \(error)")
//        }
//    }
//}
