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
    private let chunkSize: Int64 = 500_000  // e.g. 500KB
    private let maxConcurrentSegments = 5
    private let maxRetriesPerSegment = 5
    private let retryDelay: TimeInterval = 2.0
    
    // Delegates
    weak var segmentedDelegate: SegmentedDownloadManagerDelegate?
    weak var oldDelegate: DownloadManagerDelegate?
    
    // Track of active downloads (videoId -> context)
    private var activeDownloads: [String: SegmentedDownloadContext] = [:]
    
    // Persisted partial data (videoId -> DownloadMetadata)
    private var metadataList: [String: DownloadMetadata] = [:] {
        didSet {
            saveMetadataListToDisk()
        }
    }
    
    // Track HEAD tasks to cancel them if needed
    private var headTasks: [String: URLSessionDataTask] = [:]
    
    // Optional extended runtime session
    private var extendedSession: WKExtendedRuntimeSession?
    
    // ------------------------------------------------------------------------
    // NEW: Keep track of last progress reported per videoId so progress doesn’t move backwards.
    // If the URL changes, we reset this so we start fresh.
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
    
    /// Start or resume a segmented download.
    /// If there's already an active download for the same videoId, we cancel it first to avoid concurrency conflicts.
    func startDownload(videoId: String, from newURL: URL) {
        print("[SegmentedDownloadManager] startDownload(\(videoId)) => \(newURL)")
        
        // 1) Cancel any existing context
        cancelDownload(videoId: videoId)
        
        // 2) Check old metadata
        let existingMeta = metadataList[videoId]
        let oldURLString = existingMeta?.remoteURL
        let urlChanged = (oldURLString != nil) ? (oldURLString != newURL.absoluteString) : false
        
        guard let existingMeta = existingMeta, existingMeta.totalSize > 0 else {
            // No existing meta or totalSize=0 => do HEAD
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
        
        // If the URL changed
        print("[SegmentedDownloadManager] URL changed from \(oldURLString ?? "nil") to \(newURL.absoluteString).")
        let bytesDownloadedSoFar = Int64(existingMeta.finishedSegments.count) * chunkSize
        let oldRemaining = existingMeta.totalSize - bytesDownloadedSoFar
        
        // 1) HEAD the new URL
        headRequest(url: newURL, videoId: videoId) { [weak self] newSizeOrNil in
            guard let self = self else { return }
            guard let newTotalSize = newSizeOrNil, newTotalSize > 0 else {
                // HEAD for new URL failed => revert to old partial if possible
                print("[SegmentedDownloadManager] HEAD on new URL failed => attempt old partial fallback.")
                guard let oldString = oldURLString, let oldURL = URL(string: oldString) else {
                    print("[SegmentedDownloadManager] Old URL invalid => no fallback => fail.")
                    let e = NSError(domain: "SegmentedDownload", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Neither old nor new URL is valid."])
                    self.reportFailure(videoId, error: e)
                    return
                }
                
                // (FIX) If partial data exists => continue from old partial
                if !existingMeta.finishedSegments.isEmpty {
                    print("[SegmentedDownloadManager] Fallback => continuing partial data from old URL: \(oldURL).")
                    self.createContextAndStart(
                        videoId: videoId,
                        remoteURL: oldURL,
                        totalSize: existingMeta.totalSize
                    )
                } else {
                    print("[SegmentedDownloadManager] No partial data => can't fallback => fail.")
                    let e = NSError(domain: "SegmentedDownload", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "HEAD request for new URL failed, and no partial data to continue."])
                    self.reportFailure(videoId, error: e)
                }
                return
            }
            
            // 2) HEAD the old URL to see if it’s still valid
            guard let oldString = oldURLString, let oldURL = URL(string: oldString) else {
                // If old URL is invalid => just switch to new
                print("[SegmentedDownloadManager] Old URL invalid => using new URL from scratch.")
                self.switchToNewURLAndRestart(videoId: videoId, newURL: newURL)
                return
            }
            
            self.headRequest(url: oldURL, videoId: videoId) { oldOk in
                guard let _ = oldOk else {
                    // Old HEAD fails => switch to new
                    print("[SegmentedDownloadManager] Old HEAD => not valid => switching to new.")
                    self.switchToNewURLAndRestart(videoId: videoId, newURL: newURL)
                    return
                }
                
                // Both old & new valid => compare oldRemaining vs. newTotal
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
    
    /// Resume => same as startDownload
    func resumeDownload(videoId: String, from url: URL) {
        print("[SegmentedDownloadManager] resumeDownload(\(videoId)) => \(url)")
        startDownload(videoId: videoId, from: url)
    }
    
    /// Cancel tasks (including HEAD)
    func cancelDownload(videoId: String) {
        print("[SegmentedDownloadManager] Cancel \(videoId)")
        
        // Cancel HEAD
        if let headTask = headTasks[videoId] {
            headTask.cancel()
            headTasks.removeValue(forKey: videoId)
        }
        
        // Cancel in-flight tasks
        guard let ctx = activeDownloads[videoId] else {
            print("[SegmentedDownloadManager] No active context to cancel for \(videoId).")
            return
        }
        for (_, task) in ctx.tasksBySegmentIndex {
            task.cancel()
        }
        activeDownloads.removeValue(forKey: videoId)
    }
    
    /// Completely remove everything (partial data, final file, metadata)
    func removeDownloadCompletely(videoId: String) {
        print("[SegmentedDownloadManager] Removing \(videoId) completely.")
        
        // 1) Cancel
        cancelDownload(videoId: videoId)
        
        // 2) Delete partial segments + final
        deleteLocalFile(videoId: videoId)
        
        // 3) Remove from metadata
        metadataList.removeValue(forKey: videoId)
        
        // 4) Remove from active
        activeDownloads.removeValue(forKey: videoId)
        
        // 5) Remove last reported progress
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
        
        // 2) Clear metadata
        metadataList.removeAll()
        
        // 3) Delete the metadata JSON file
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
    
    /// Deletes final MP4 & partial chunks
    func deleteLocalFile(videoId: String) {
        print("[SegmentedDownloadManager] deleteLocalFile => \(videoId)")
        
        cancelDownload(videoId: videoId)
        
        let finalURL = localFileURL(videoId: videoId)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try? FileManager.default.removeItem(at: finalURL)
            print("[SegmentedDownloadManager] Deleted .mp4 for \(videoId).")
        }
        
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
        
        // Count how many chunk files are on disk
        let totalSegs = ctx.totalSegments
        var diskCount = 0
        for i in 0..<totalSegs {
            let segURL = tempSegmentURL(videoId: videoId, index: i)
            if FileManager.default.fileExists(atPath: segURL.path) {
                diskCount += 1
                // If we see a partial file on disk not in metadata, add it
                if !(metadataList[videoId]?.finishedSegments.contains(i) ?? false) {
                    metadataList[videoId]?.finishedSegments.append(i)
                }
                // Bump completedBytes by the chunk’s actual size
                if let fileAttrs = try? FileManager.default.attributesOfItem(atPath: segURL.path),
                   let fileSize = fileAttrs[.size] as? Int64 {
                    ctx.completedBytes += fileSize
                }
            }
        }
        print("[SegmentedDownloadManager] \(videoId) => \(diskCount) chunk files found on disk.")
        
        // Mark active
        activeDownloads[videoId] = ctx
        scheduleChunkDownloads(ctx)
    }
    
    private func scheduleChunkDownloads(_ ctx: SegmentedDownloadContext) {
        let videoId = ctx.videoId
        guard let meta = metadataList[videoId] else { return }
        
        let totalSegs = ctx.totalSegments
        let doneSet = Set(meta.finishedSegments)
        
        ctx.pendingSegments = (0..<totalSegs).filter { !doneSet.contains($0) }
        
        print("[SegmentedDownloadManager] \(videoId) => totalSegs=\(totalSegs), pending=\(ctx.pendingSegments.count)")
        
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
                  let data = data, !data.isEmpty else {
                let e = NSError(domain: "SegmentedDownload", code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "Invalid response or empty data."])
                self.handleChunkError(ctx, segIndex: segIndex, error: e)
                return
            }
            
            do {
                // Save chunk
                let segURL = self.tempSegmentURL(videoId: videoId, index: segIndex)
                try data.write(to: segURL, options: .atomic)
                
                // Mark finished
                if var meta = self.metadataList[videoId] {
                    if !meta.finishedSegments.contains(segIndex) {
                        meta.finishedSegments.append(segIndex)
                        self.metadataList[videoId] = meta
                    }
                }
                
                ctx.completedBytes += Int64(data.count)
                
                // Clamp progress
                var fraction = Double(ctx.completedBytes) / Double(ctx.totalSize)
                let lastFrac = self.lastReportedProgress[videoId] ?? 0.0
                if fraction < lastFrac {
                    fraction = lastFrac
                } else {
                    self.lastReportedProgress[videoId] = fraction
                }
                
                // Notify
                self.segmentedDelegate?.segmentedDownloadDidUpdateProgress(videoId: videoId, progress: fraction)
                self.oldDelegate?.downloadDidUpdateProgress(
                    videoId: videoId,
                    receivedBytes: Int64(Double(fraction) * Double(ctx.totalSize)),
                    totalBytes: ctx.totalSize
                )
                
                // Next segment
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
            print("[SegmentedDownloadManager] [ERROR] #\(segIndex) => \(error). Retrying(\(attempts + 1)).")
            
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
        
        // Mark 100%
        lastReportedProgress[videoId] = 1.0
        segmentedDelegate?.segmentedDownloadDidUpdateProgress(videoId: videoId, progress: 1.0)
        oldDelegate?.downloadDidUpdateProgress(
            videoId: videoId,
            receivedBytes: ctx.totalSize,
            totalBytes: ctx.totalSize
        )
        
        // Remove from active + metadata
        activeDownloads.removeValue(forKey: videoId)
        metadataList.removeValue(forKey: videoId)
        
        segmentedDelegate?.segmentedDownloadDidComplete(videoId: videoId, fileURL: finalURL)
        oldDelegate?.downloadDidComplete(videoId: videoId, localFileURL: finalURL)
        
        // Clean up
        lastReportedProgress.removeValue(forKey: videoId)
    }
    
    private func reportFailure(_ videoId: String, error: Error) {
        print("[SegmentedDownloadManager] [ERROR] \(videoId) => \(error)")
        
        // Remove from active
        activeDownloads.removeValue(forKey: videoId)
        
        // Also remove last progress
        lastReportedProgress.removeValue(forKey: videoId)
        
        segmentedDelegate?.segmentedDownloadDidFail(videoId: videoId, error: error)
        oldDelegate?.downloadDidFail(videoId: videoId, error: error)
    }
    
    // MARK: - Network Helpers
    
    private func headRequest(url: URL, videoId: String, completion: @escaping (Int64?) -> Void) {
        // Cancel any existing HEAD for this videoId
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
    
    /// Clear old partial data, reset metadata, then do HEAD on the new URL
    private func switchToNewURLAndRestart(videoId: String, newURL: URL) {
        deleteLocalFile(videoId: videoId)
        
        metadataList[videoId] = DownloadMetadata(
            videoId: videoId,
            remoteURL: newURL.absoluteString,
            totalSize: 0,
            finishedSegments: []
        )
        
        lastReportedProgress.removeValue(forKey: videoId)
        
        doHeadAndStart(videoId: videoId, url: newURL)
    }
    
    /// HEAD + create context, or fallback to partial if HEAD fails but partial data exists
    private func doHeadAndStart(videoId: String, url: URL) {
        let existingMeta = metadataList[videoId]
        let partialExists = !(existingMeta?.finishedSegments.isEmpty ?? true)
        
        headRequest(url: url, videoId: videoId) { [weak self] totalSize in
            guard let self = self else { return }
            
            // If user canceled mid-HEAD
            if self.activeDownloads[videoId] != nil {
                print("[SegmentedDownloadManager] doHeadAndStart => Found an active context, not proceeding.")
                return
            }
            
            guard let totalSize = totalSize, totalSize > 0 else {
                // (FIX) If HEAD fails but partial exists => continue
                if partialExists, let meta = existingMeta {
                    print("[SegmentedDownloadManager] doHeadAndStart => HEAD failed but partial data found => continuing partial.")
                    DispatchQueue.main.async {
                        let oldURLString = meta.remoteURL
                        if let oldURL = URL(string: oldURLString) {
                            self.createContextAndStart(videoId: videoId, remoteURL: oldURL, totalSize: meta.totalSize)
                        } else {
                            // no fallback => fail
                            let e = NSError(domain: "SegmentedDownload", code: 2,
                                            userInfo: [NSLocalizedDescriptionKey: "HEAD fail + fallback parse error."])
                            self.reportFailure(videoId, error: e)
                        }
                    }
                } else {
                    // no partial => fail
                    let e = NSError(
                        domain: "SegmentedDownload",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "HEAD request failed & no partial data available."
                        ]
                    )
                    self.reportFailure(videoId, error: e)
                }
                return
            }
            
            // HEAD success => continue
            self.metadataList[videoId] = DownloadMetadata(
                videoId: videoId,
                remoteURL: url.absoluteString,
                totalSize: totalSize,
                finishedSegments: []
            )
            
            self.lastReportedProgress.removeValue(forKey: videoId)
            
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
    
    /// Mapping segmentIndex => URLSessionDataTask
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
