import Foundation
import WatchKit

// MARK: - SegmentedDownloadManager
class SegmentedDownloadManager: NSObject {
    
    static let shared = SegmentedDownloadManager()
    
    private override init() {
        super.init()
        
        // Load partial metadata from disk
        metadataList = loadMetadataListFromDisk()
        
        // Ensure partial chunks on disk align with metadata
        refreshLocalSegmentsForAll()
    }
    
    // Two domain aliases to bypass single-host concurrency
    private let domainA = "https://dwxvsu8u3eeuu.cloudfront.net"
    private let domainB = "https://apple-watchclips.s3.eu-west-2.amazonaws.com"
    
    // URLSession with ephemeral config
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 180
        config.allowsExpensiveNetworkAccess = true
        config.httpMaximumConnectionsPerHost = 5
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.networkServiceType = .responsiveData
        return URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }()
    
    // Tuning
    private let chunkSize: Int64 = 500_000       // e.g. 500 KB
    private let maxConcurrentSegments = 5
    private let maxRetriesPerSegment = 5
    private let retryDelay: TimeInterval = 2.0
    
    // Delegates
    weak var segmentedDelegate: SegmentedDownloadManagerDelegate?
    weak var oldDelegate: DownloadManagerDelegate?
    
    // Keep track of active downloads (videoId -> context)
    private var activeDownloads: [String: SegmentedDownloadContext] = [:]
    
    // Persisted partial data (videoId -> DownloadMetadata)
    private var metadataList: [String: DownloadMetadata] = [:] {
        didSet {
            saveMetadataListToDisk()
        }
    }
    
    // Track HEAD tasks so we can cancel them if needed
    private var headTasks: [String: URLSessionDataTask] = [:]
    
    // Extended runtime session (optional)
    private var extendedSession: WKExtendedRuntimeSession?

    // ------------------------------------------------------------------------
    // Track the last progress we reported per videoId so progress never moves backward
    // for the same URL. But if the URL has changed, we reset this to start fresh.
    // ------------------------------------------------------------------------
    private var lastReportedProgress: [String: Double] = [:]
    
    // MARK: - Extended Runtime Session
    
    func beginExtendedRuntimeSession() {
        guard extendedSession == nil else {
            print("[SegmentedDownloadManager] Extended session already active.")
            return
        }
        
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        extendedSession = session
        session.start()
        print("[SegmentedDownloadManager] Extended runtime session started.")
    }
    
    func endExtendedRuntimeSession() {
        extendedSession?.invalidate()
        extendedSession = nil
        print("[SegmentedDownloadManager] Extended runtime session invalidated.")
    }
    
    // MARK: - Public API
    
    func clearAllActiveDownloads() {
        print("[SegmentedDownloadManager] Clearing all active downloads.")

        let activeIds = activeDownloads.keys
        for videoId in activeIds {
            removeDownloadCompletely(videoId: videoId)
        }
    }
    
    /// Starts or resumes a download from scratch or continues partial data.
    /// If there's already an active download for the same videoId, we cancel it first.
    func startDownload(videoId: String, from newURL: URL) {
        print("[SegmentedDownloadManager] startDownload(\(videoId)) => \(newURL)")
        
        // 1) Immediately cancel any existing active context for this video
        cancelDownload(videoId: videoId)
        
        // 2) Check old metadata for URL changes, etc.
        let existingMeta = metadataList[videoId]
        let oldURLString = existingMeta?.remoteURL
        let urlChanged = (oldURLString != nil) ? (oldURLString != newURL.absoluteString) : false
        
        // If no existing meta or totalSize=0 => HEAD new URL
        guard let existingMeta = existingMeta, existingMeta.totalSize > 0 else {
            doHeadAndStart(videoId: videoId, url: newURL)
            return
        }
        
        // If the URL did not change => continue old partial
        if !urlChanged {
            print("[SegmentedDownloadManager] URL not changed => continuing existing partial data.")
            guard let oldString = oldURLString, let oldURL = URL(string: oldString) else {
                let e = NSError(domain: "SegmentedDownload", code: -2,
                                userInfo: [NSLocalizedDescriptionKey: "Invalid stored URL."])
                self.reportFailure(videoId, error: e)
                return
            }
            createContextAndStart(videoId: videoId, remoteURL: oldURL, totalSize: existingMeta.totalSize)
            return
        }
        
        // URL changed => Decide if we keep old partial or start new
        print("[SegmentedDownloadManager] URL changed from \(oldURLString ?? "nil") to \(newURL.absoluteString).")
        
        let bytesDownloadedSoFar = Int64(existingMeta.finishedSegments.count) * chunkSize
        let oldRemaining = existingMeta.totalSize - bytesDownloadedSoFar
        
        // 1) HEAD the new URL
        headRequest(url: newURL, videoId: videoId) { [weak self] newSizeOrNil in
            guard let self = self else { return }
            guard let newTotalSize = newSizeOrNil, newTotalSize > 0 else {
                // HEAD failed => revert to old partial
                print("[SegmentedDownloadManager] HEAD on new URL failed => keep old partial progress.")
                guard let oldString = oldURLString, let oldURL = URL(string: oldString) else {
                    print("[SegmentedDownloadManager] Old URL invalid => no fallback => fail.")
                    let e = NSError(domain: "SegmentedDownload", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Neither old nor new URL valid."])
                    self.reportFailure(videoId, error: e)
                    return
                }
                self.createContextAndStart(videoId: videoId, remoteURL: oldURL, totalSize: existingMeta.totalSize)
                return
            }
            
            // 2) HEAD the old URL
            guard let oldString = oldURLString, let oldURL = URL(string: oldString) else {
                print("[SegmentedDownloadManager] Old URL invalid => using new URL from scratch.")
                self.switchToNewURLAndRestart(videoId: videoId, newURL: newURL)
                return
            }
            
            self.headRequest(url: oldURL, videoId: videoId) { oldOk in
                // If old HEAD fails => start new
                guard let _ = oldOk else {
                    print("[SegmentedDownloadManager] Old HEAD => not valid => switching to new.")
                    self.switchToNewURLAndRestart(videoId: videoId, newURL: newURL)
                    return
                }
                
                // Both old + new are valid => compare oldRemaining vs. newTotalSize
                print("[SegmentedDownloadManager] oldRemaining=\(oldRemaining), newTotal=\(newTotalSize).")
                if oldRemaining < newTotalSize {
                    // Continue old partial
                    self.createContextAndStart(videoId: videoId, remoteURL: oldURL, totalSize: existingMeta.totalSize)
                } else {
                    // Switch to new
                    self.switchToNewURLAndRestart(videoId: videoId, newURL: newURL)
                }
            }
        }
    }

    func resumeDownload(videoId: String, from url: URL) {
        print("[SegmentedDownloadManager] resumeDownload(\(videoId)) => \(url)")
        startDownload(videoId: videoId, from: url)
    }
    
    /// Cancel all in-flight tasks (including HEAD)
    func cancelDownload(videoId: String) {
        print("[SegmentedDownloadManager] Cancel \(videoId)")
        
        // Cancel HEAD
        if let headTask = headTasks[videoId] {
            headTask.cancel()
            headTasks.removeValue(forKey: videoId)
        }
        
        // Cancel active context tasks
        guard let ctx = activeDownloads[videoId] else {
            print("[SegmentedDownloadManager] No active context to cancel for \(videoId).")
            return
        }
        for (_, task) in ctx.tasksBySegmentIndex {
            task.cancel()
        }
        activeDownloads.removeValue(forKey: videoId)
    }
    
    /// Completely remove (cancel tasks + partial chunks + final file + metadata)
    func removeDownloadCompletely(videoId: String) {
        print("[SegmentedDownloadManager] Removing \(videoId) completely.")
        
        // 1) Cancel
        cancelDownload(videoId: videoId)
        
        // 2) Delete partial + final
        deleteLocalFile(videoId: videoId)
        
        // 3) Remove from metadata
        metadataList.removeValue(forKey: videoId)
        
        // 4) Remove from activeDownloads just in case
        activeDownloads.removeValue(forKey: videoId)
        
        // 5) Remove last progress so next time we start fresh
        lastReportedProgress.removeValue(forKey: videoId)
    }
    
    func deleteAllSavedVideos() {
        for video in DownloadsStore.shared.loadDownloads() {
            removeDownloadCompletely(videoId: video.id)
        }
    }

    func wipeAllDownloadsCompletely() {
        print("[SegmentedDownloadManager] Wiping everything clean!")

        // 1) Cancel and remove all active
        clearAllActiveDownloads()

        // 2) Remove entire metadataList
        metadataList.removeAll()

        // 3) Remove the metadata JSON file
        let metaListFile = metadataListURL()
        if FileManager.default.fileExists(atPath: metaListFile.path) {
            try? FileManager.default.removeItem(at: metaListFile)
            print("[SegmentedDownloadManager] Removed metadataList file => \(metaListFile.lastPathComponent)")
        }

        // 4) Remove all .mp4 in caches
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        do {
            let allCacheFiles = try FileManager.default.contentsOfDirectory(atPath: cachesDir.path)
            for fileName in allCacheFiles where fileName.hasSuffix(".mp4") {
                let fileURL = cachesDir.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: fileURL)
                print("[SegmentedDownloadManager] Removed => \(fileURL.lastPathComponent)")
            }
        } catch {
            print("[SegmentedDownloadManager] [ERROR] reading cachesDir => \(error)")
        }

        // 5) Remove partial segments from temp
        let tmpDir = FileManager.default.temporaryDirectory
        do {
            let allTempFiles = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
            for fileName in allTempFiles where fileName.contains("_part") {
                let fileURL = tmpDir.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: fileURL)
                print("[SegmentedDownloadManager] Removed => \(fileURL.lastPathComponent)")
            }
        } catch {
            print("[SegmentedDownloadManager] [ERROR] reading tempDir => \(error)")
        }

        print("[SegmentedDownloadManager] All downloads wiped - clean slate!")
    }

    /// Deletes final MP4 & any partial segments for given videoId.
    func deleteLocalFile(videoId: String) {
        print("[SegmentedDownloadManager] deleteLocalFile => \(videoId)")
        
        // Cancel tasks so we don't keep writing chunks
        cancelDownload(videoId: videoId)
        
        // 1) Delete .mp4
        let finalURL = localFileURL(videoId: videoId)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try? FileManager.default.removeItem(at: finalURL)
            print("[SegmentedDownloadManager] Deleted .mp4 for \(videoId).")
        }
        
        // 2) Delete partial segments
        if let meta = metadataList[videoId] {
            let totalSegs = meta.numberOfSegments(chunkSize: chunkSize)
            for i in 0..<totalSegs {
                let segURL = tempSegmentURL(videoId: videoId, index: i)
                try? FileManager.default.removeItem(at: segURL)
            }
            print("[SegmentedDownloadManager] Deleted partial segments for \(videoId).")
        } else {
            // Fallback if no metadata
            let fileManager = FileManager.default
            let tmpDir = fileManager.temporaryDirectory
            if let enumerator = fileManager.enumerator(atPath: tmpDir.path) {
                for case let fileName as String in enumerator {
                    if fileName.hasPrefix("\(videoId)_part") {
                        let fileURL = tmpDir.appendingPathComponent(fileName)
                        try? fileManager.removeItem(at: fileURL)
                    }
                }
            }
            print("[SegmentedDownloadManager] Deleted partial segments for \(videoId) via fallback.")
        }
    }

    func isTaskActive(videoId: String) -> Bool {
        return activeDownloads[videoId] != nil
    }
    
    func hasResumeData(for videoId: String) -> Bool {
        guard let meta = metadataList[videoId] else { return false }
        return !meta.finishedSegments.isEmpty
    }
    
    func doesLocalFileExist(videoId: String) -> Bool {
        FileManager.default.fileExists(atPath: localFileURL(videoId: videoId).path)
    }
    
    // MARK: - Internal Context Creation
    
    private func createContextAndStart(videoId: String, remoteURL: URL, totalSize: Int64) {
        // Fresh context
        let ctx = SegmentedDownloadContext(
            videoId: videoId,
            remoteURL: remoteURL,
            totalSize: totalSize,
            segmentSize: chunkSize,
            maxRetries: maxRetriesPerSegment
        )
        
        // If partial data exists, reflect it
        if let meta = metadataList[videoId] {
            for seg in meta.finishedSegments {
                ctx.segmentRetryCount[seg] = 0
            }
        }
        
        // Count how many chunks are on disk
        let totalSegs = ctx.totalSegments
        var diskCount = 0
        for i in 0..<totalSegs {
            let segURL = tempSegmentURL(videoId: videoId, index: i)
            if FileManager.default.fileExists(atPath: segURL.path) {
                diskCount += 1
                // If we see a segment file on disk not in metadata, add it
                if !(metadataList[videoId]?.finishedSegments.contains(i) ?? false) {
                    metadataList[videoId]?.finishedSegments.append(i)
                }
                // Also increment context’s completedBytes by the actual file size
                if let fileAttrs = try? FileManager.default.attributesOfItem(atPath: segURL.path),
                   let fileSize = fileAttrs[.size] as? Int64 {
                    ctx.completedBytes += fileSize
                }
            }
        }
        
        print("[SegmentedDownloadManager] \(videoId) => \(diskCount) chunk files found on disk.")
        
        // Mark it active
        activeDownloads[videoId] = ctx
        
        // Kick off concurrency
        scheduleChunkDownloads(ctx)
    }
    
    private func scheduleChunkDownloads(_ ctx: SegmentedDownloadContext) {
        let videoId = ctx.videoId
        guard let meta = metadataList[videoId] else { return }
        
        let totalSegs = ctx.totalSegments
        let doneSet = Set(meta.finishedSegments)
        
        // Build pending
        ctx.pendingSegments = (0..<totalSegs).filter { !doneSet.contains($0) }
        
        print("[SegmentedDownloadManager] \(videoId) => totalSegs=\(totalSegs), pending=\(ctx.pendingSegments.count)")
        
        // Start concurrency
        for _ in 0..<maxConcurrentSegments {
            startNextSegmentIfAvailable(ctx)
        }
    }
    
    private func startNextSegmentIfAvailable(_ ctx: SegmentedDownloadContext) {
        let videoId = ctx.videoId
        
        guard activeDownloads[videoId] != nil else { return }
        
        // If done
        if ctx.pendingSegments.isEmpty && ctx.inFlightSegments.isEmpty {
            concatenateSegments(ctx)
            return
        }
        
        guard !ctx.pendingSegments.isEmpty else { return }
        
        let segIndex = ctx.pendingSegments.removeFirst()
        ctx.inFlightSegments.insert(segIndex)
        
        // Decide domain
        let isEven = (segIndex % 2 == 0)
        let chosenDomain = isEven ? domainA : domainB
        
        let originalPath = ctx.remoteURL.path
        let altString = chosenDomain + originalPath
        guard let altURL = URL(string: altString) else {
            print("[SegmentedDownloadManager] [WARNING] Could not build altURL => fallback to original domain.")
            startSegmentRequest(ctx: ctx, segIndex: segIndex, requestURL: ctx.remoteURL)
            return
        }
        
        startSegmentRequest(ctx: ctx, segIndex: segIndex, requestURL: altURL)
    }
    
    private func startSegmentRequest(ctx: SegmentedDownloadContext, segIndex: Int, requestURL: URL) {
        let videoId = ctx.videoId
        let startByte = ctx.segmentSize * Int64(segIndex)
        let endByte = min(startByte + ctx.segmentSize - 1, ctx.totalSize - 1)
        
        var req = URLRequest(url: requestURL)
        req.httpMethod = "GET"
        req.setValue("bytes=\(startByte)-\(endByte)", forHTTPHeaderField: "Range")
        
        let task = urlSession.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { return }
            
            // If canceled mid-way
            guard self.activeDownloads[videoId] != nil else {
                print("[SegmentedDownloadManager] \(videoId) seg #\(segIndex) => canceled mid-request.")
                return
            }
            
            ctx.inFlightSegments.remove(segIndex)
            ctx.tasksBySegmentIndex.removeValue(forKey: segIndex)
            
            if let e = error {
                self.handleChunkError(ctx, segIndex: segIndex, error: e)
                return
            }
            
            guard let httpRes = response as? HTTPURLResponse,
                  (httpRes.statusCode == 206 || httpRes.statusCode == 200),
                  let data = data,
                  !data.isEmpty
            else {
                let e = NSError(domain: "SegmentedDownload", code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "Invalid response or empty data."])
                self.handleChunkError(ctx, segIndex: segIndex, error: e)
                return
            }
            
            do {
                // Write chunk to temp
                let segURL = self.tempSegmentURL(videoId: videoId, index: segIndex)
                try data.write(to: segURL, options: .atomic)
                
                // Update metadata
                if var meta = self.metadataList[videoId] {
                    if !meta.finishedSegments.contains(segIndex) {
                        meta.finishedSegments.append(segIndex)
                        self.metadataList[videoId] = meta
                    }
                }
                
                // Update context's downloaded bytes
                ctx.completedBytes += Int64(data.count)
                
                // ----------------------------------------------------------------
                // Clamp progress so it never moves backwards for the same URL
                // ----------------------------------------------------------------
                var fraction = Double(ctx.completedBytes) / Double(ctx.totalSize)
                let lastFrac = self.lastReportedProgress[videoId] ?? 0.0
                if fraction < lastFrac {
                    fraction = lastFrac
                } else {
                    self.lastReportedProgress[videoId] = fraction
                }
                
                // Notify progress
                self.segmentedDelegate?.segmentedDownloadDidUpdateProgress(videoId: videoId, progress: fraction)
                self.oldDelegate?.downloadDidUpdateProgress(
                    videoId: videoId,
                    receivedBytes: Int64(Double(fraction) * Double(ctx.totalSize)),
                    totalBytes: ctx.totalSize
                )
                
                // Attempt next segment
                self.startNextSegmentIfAvailable(ctx)
                
            } catch {
                self.handleChunkError(ctx, segIndex: segIndex, error: error)
            }
        }
        
        ctx.tasksBySegmentIndex[segIndex] = task
        task.resume()
    }
    
    private func handleChunkError(_ ctx: SegmentedDownloadContext, segIndex: Int, error: Error) {
        ctx.inFlightSegments.remove(segIndex)
        ctx.tasksBySegmentIndex.removeValue(forKey: segIndex)
        
        let attempts = ctx.segmentRetryCount[segIndex] ?? 0
        if attempts < ctx.maxRetries {
            ctx.segmentRetryCount[segIndex] = attempts + 1
            print("[SegmentedDownloadManager] [ERROR] #\(segIndex) => \(error). Retrying(\(attempts+1)).")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                guard self.activeDownloads[ctx.videoId] != nil else { return }
                ctx.pendingSegments.insert(segIndex, at: 0)
                self.startNextSegmentIfAvailable(ctx)
            }
        } else {
            print("[SegmentedDownloadManager] [ERROR] #\(segIndex) => too many retries => fail.")
            reportFailure(ctx.videoId, error: error)
        }
    }
    
    private func concatenateSegments(_ ctx: SegmentedDownloadContext) {
        let videoId = ctx.videoId
        print("[SegmentedDownloadManager] \(videoId) => All segments done, concatenating.")
        
        let finalURL = localFileURL(videoId: videoId)
        try? FileManager.default.removeItem(at: finalURL)
        FileManager.default.createFile(atPath: finalURL.path, contents: nil, attributes: nil)
        
        guard let handle = try? FileHandle(forWritingTo: finalURL) else {
            let e = NSError(domain: "SegmentedDownloadManager", code: 10,
                            userInfo: [NSLocalizedDescriptionKey: "Could not open final file handle"])
            reportFailure(videoId, error: e)
            return
        }
        
        let totalSegs = ctx.totalSegments
        for i in 0..<totalSegs {
            let segURL = tempSegmentURL(videoId: videoId, index: i)
            if !FileManager.default.fileExists(atPath: segURL.path) {
                let e = NSError(domain: "SegmentedDownloadManager", code: 11,
                                userInfo: [NSLocalizedDescriptionKey: "Missing segment #\(i)."])
                handle.closeFile()
                reportFailure(videoId, error: e)
                return
            }
            do {
                let data = try Data(contentsOf: segURL)
                handle.seekToEndOfFile()
                handle.write(data)
            } catch {
                handle.closeFile()
                reportFailure(videoId, error: error)
                return
            }
        }
        handle.closeFile()
        
        // Remove partial segments
        for i in 0..<totalSegs {
            let segURL = tempSegmentURL(videoId: videoId, index: i)
            try? FileManager.default.removeItem(at: segURL)
        }
        
        // Mark final progress = 100%
        lastReportedProgress[videoId] = 1.0
        segmentedDelegate?.segmentedDownloadDidUpdateProgress(videoId: videoId, progress: 1.0)
        oldDelegate?.downloadDidUpdateProgress(
            videoId: videoId,
            receivedBytes: ctx.totalSize,
            totalBytes: ctx.totalSize
        )
        
        // Remove from active + remove metadata
        activeDownloads.removeValue(forKey: videoId)
        metadataList.removeValue(forKey: videoId)
        
        segmentedDelegate?.segmentedDownloadDidComplete(videoId: videoId, fileURL: finalURL)
        oldDelegate?.downloadDidComplete(videoId: videoId, localFileURL: finalURL)
        
        // Clean up last progress so next time we start fresh
        lastReportedProgress.removeValue(forKey: videoId)
    }
    
    private func reportFailure(_ videoId: String, error: Error) {
        print("[SegmentedDownloadManager] [ERROR] \(videoId) => \(error)")
        
        // Remove from active
        activeDownloads.removeValue(forKey: videoId)
        
        // Also remove last reported progress
        lastReportedProgress.removeValue(forKey: videoId)
        
        segmentedDelegate?.segmentedDownloadDidFail(videoId: videoId, error: error)
        oldDelegate?.downloadDidFail(videoId: videoId, error: error)
    }
    
    // MARK: - Network Helpers
    
    private func headRequest(url: URL, videoId: String, completion: @escaping (Int64?) -> Void) {
        // Cancel existing HEAD for this videoId
        if let existingHead = headTasks[videoId] {
            existingHead.cancel()
            headTasks.removeValue(forKey: videoId)
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        
        let task = urlSession.dataTask(with: req) { [weak self] _, response, error in
            guard let self = self else { return }
            self.headTasks.removeValue(forKey: videoId)
            
            if let err = error {
                print("[SegmentedDownloadManager] headRequest(\(url)) => error: \(err)")
                completion(nil)
                return
            }
            guard let httpRes = response as? HTTPURLResponse,
                  (httpRes.statusCode == 200 || httpRes.statusCode == 206),
                  let lengthStr = httpRes.allHeaderFields["Content-Length"] as? String,
                  let size = Int64(lengthStr),
                  size > 0
            else {
                print("[SegmentedDownloadManager] headRequest(\(url)) => not 200/206 or no Content-Length.")
                completion(nil)
                return
            }
            
            completion(size)
        }
        
        headTasks[videoId] = task
        task.resume()
    }
    
    /// Clear old partial data, reset metadata, then HEAD new URL.
    private func switchToNewURLAndRestart(videoId: String, newURL: URL) {
        deleteLocalFile(videoId: videoId)
        
        // Clear old metadata => start fresh
        metadataList[videoId] = DownloadMetadata(
            videoId: videoId,
            remoteURL: newURL.absoluteString,
            totalSize: 0,
            finishedSegments: []
        )
        
        // (ADDED) Reset lastReportedProgress so progress begins at 0 for the new URL
        lastReportedProgress.removeValue(forKey: videoId)  // (ADDED)
        
        doHeadAndStart(videoId: videoId, url: newURL)
    }
    
    /// Common helper: does a HEAD and creates the context if possible.
    private func doHeadAndStart(videoId: String, url: URL) {
        headRequest(url: url, videoId: videoId) { [weak self] totalSize in
            guard let self = self else { return }
            
            // If the user canceled in the meantime
            if self.activeDownloads[videoId] != nil {
                print("[SegmentedDownloadManager] doHeadAndStart => Found an active context, not proceeding.")
                return
            }
            
            guard let totalSize = totalSize, totalSize > 0 else {
                let e = NSError(
                    domain: "SegmentedDownload",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "The file was not found on the server. Please contact support at support@watchclips.app if this issue persists."
                    ]
                )
                self.reportFailure(videoId, error: e)
                return
            }
            
            // Update metadata
            self.metadataList[videoId] = DownloadMetadata(
                videoId: videoId,
                remoteURL: url.absoluteString,
                totalSize: totalSize,
                finishedSegments: []
            )
            
            // (ADDED) Also make sure we reset progress to 0
            self.lastReportedProgress.removeValue(forKey: videoId)  // (ADDED)
            
            // Create context & start
            self.createContextAndStart(videoId: videoId, remoteURL: url, totalSize: totalSize)
        }
    }
    
    // MARK: - Disk Helpers
    
    func localFileURL(videoId: String) -> URL {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesDir.appendingPathComponent("\(videoId).mp4")
    }
    
    func tempSegmentURL(videoId: String, index: Int) -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
        return tmpDir.appendingPathComponent("\(videoId)_part\(index).tmp")
    }
    
    // MARK: - Persistence
    
    private func saveMetadataListToDisk() {
        do {
            let array = Array(metadataList.values)
            let data = try JSONEncoder().encode(array)
            let url = metadataListURL()
            try data.write(to: url, options: .atomic)
            print("[SegmentedDownloadManager] Saved metadataList => \(url.lastPathComponent)")
        } catch {
            print("[SegmentedDownloadManager] [ERROR] saving metadata => \(error)")
        }
    }
    
    private func loadMetadataListFromDisk() -> [String: DownloadMetadata] {
        let url = metadataListURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            let data = try Data(contentsOf: url)
            let array = try JSONDecoder().decode([DownloadMetadata].self, from: data)
            var dict = [String: DownloadMetadata]()
            for item in array {
                dict[item.videoId] = item
            }
            return dict
        } catch {
            print("[SegmentedDownloadManager] [ERROR] loading metadata => \(error)")
            return [:]
        }
    }
    
    private func metadataListURL() -> URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cacheDir.appendingPathComponent("SegmentedDownloads.json")
    }
    
    private func refreshLocalSegmentsForAll() {
        for (videoId, meta) in metadataList {
            let totalSegs = meta.numberOfSegments(chunkSize: chunkSize)
            var onDisk: [Int] = []
            for i in 0..<totalSegs {
                let segURL = tempSegmentURL(videoId: videoId, index: i)
                if FileManager.default.fileExists(atPath: segURL.path) {
                    onDisk.append(i)
                }
            }
            let unionSet = Set(onDisk).union(Set(meta.finishedSegments)).sorted()
            metadataList[videoId] = meta.withFinishedSegments(unionSet)
        }
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate
extension SegmentedDownloadManager: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                error: (any Error)?) {
        print("[SegmentedDownloadManager] extendedRuntimeSession(didInvalidateWith) reason=\(reason) error=\(String(describing: error))")
        extendedSession = nil
    }
    
    @objc func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("[SegmentedDownloadManager] extendedRuntimeSessionDidStart.")
    }
    
    @objc func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("[SegmentedDownloadManager] extendedRuntimeSessionWillExpire => Ending soon.")
    }
    
    @objc func extendedRuntimeSessionDidInvalidate(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("[SegmentedDownloadManager] extendedRuntimeSessionDidInvalidate => Session ended.")
        extendedSession = nil
    }
}

// MARK: - SegmentedDownloadContext
private class SegmentedDownloadContext {
    let videoId: String
    let remoteURL: URL
    let totalSize: Int64
    let segmentSize: Int64
    let maxRetries: Int
    
    var totalSegments: Int {
        let numerator = totalSize + (segmentSize - 1)
        return Int(numerator / segmentSize)
    }
    
    var pendingSegments: [Int] = []
    var inFlightSegments: Set<Int> = []
    var tasksBySegmentIndex: [Int: URLSessionDataTask] = [:]
    var completedBytes: Int64 = 0
    var segmentRetryCount: [Int: Int] = [:]
    
    init(videoId: String,
         remoteURL: URL,
         totalSize: Int64,
         segmentSize: Int64,
         maxRetries: Int) {
        self.videoId = videoId
        self.remoteURL = remoteURL
        self.totalSize = totalSize
        self.segmentSize = segmentSize
        self.maxRetries = maxRetries
    }
}

// MARK: - DownloadMetadata
struct DownloadMetadata: Codable {
    let videoId: String
    let remoteURL: String
    let totalSize: Int64
    var finishedSegments: [Int]
    
    func numberOfSegments(chunkSize: Int64) -> Int {
        let numerator = totalSize + (chunkSize - 1)
        return Int(numerator / chunkSize)
    }
    
    func withRemoteURL(_ newURL: String) -> DownloadMetadata {
        DownloadMetadata(
            videoId: videoId,
            remoteURL: newURL,
            totalSize: totalSize,
            finishedSegments: finishedSegments
        )
    }
    
    func withFinishedSegments(_ segments: [Int]) -> DownloadMetadata {
        DownloadMetadata(
            videoId: videoId,
            remoteURL: remoteURL,
            totalSize: totalSize,
            finishedSegments: segments
        )
    }
}
