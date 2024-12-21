//
//  ResumeCapableDownloader.swift
//  WatchClips Watch App
//
//  Created by Zakariya Hassan on 18/12/2024.
//

import Foundation

class ResumeCapableDownloader: NSObject, URLSessionDataDelegate {
    private let remoteURL: URL
    private let segments: [(index: Int, range: ClosedRange<Int64>)]
    private let segmentsDir: URL
    private let completionHandler: (Result<Void, Error>) -> Void

    private var maxConcurrentDownloads: Int
    private var sessionConfiguration: URLSessionConfiguration
    private var session: URLSession?

    private let lock = NSLock()
    private var segmentDataMap = [Int: Data]()

    private var segmentQueue: [(index: Int, range: ClosedRange<Int64>)] = []
    private var runningTasks = 0
    private var totalTasks = 0
    private var finished = false
    
    // New progress tracking variables
    private var completedSegments = 0

    init(remoteURL: URL,
         segments: [(Int, ClosedRange<Int64>)],
         segmentsDir: URL,
         maxConcurrentDownloads: Int = 1,
         sessionConfiguration: URLSessionConfiguration = .default,
         completion: @escaping (Result<Void, Error>) -> Void) {
        
        self.remoteURL = remoteURL
        self.segments = segments
        self.segmentsDir = segmentsDir
        self.completionHandler = completion
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.sessionConfiguration = sessionConfiguration
        
        super.init()
        
        self.segmentQueue = segments
        self.totalTasks = segments.count
        self.completedSegments = 0
    }

    func start() {
        print("[DOWNLOAD] Starting download with \(totalTasks) segments. Max concurrency: \(maxConcurrentDownloads)")
        
        sessionConfiguration.httpMaximumConnectionsPerHost = max(maxConcurrentDownloads, 1)
        session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)

        startNextSegmentsIfPossible()
    }

    private func startNextSegmentsIfPossible() {
        lock.lock()
        defer { lock.unlock() }

        guard !finished else { return }

        while runningTasks < maxConcurrentDownloads && !segmentQueue.isEmpty {
            let (index, range) = segmentQueue.removeFirst()
            var request = URLRequest(url: remoteURL)
            request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")

            guard let session = session else {
                print("[DOWNLOAD] Session is nil, cannot start task for segment \(index)")
                continue
            }

            let task = session.dataTask(with: request)
            task.taskDescription = "\(index)"
            runningTasks += 1
            print("[DOWNLOAD] Starting segment \(index) with range: \(range.lowerBound)-\(range.upperBound)")
            task.resume()
        }
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        defer { lock.unlock() }

        guard let taskDesc = dataTask.taskDescription, let index = Int(taskDesc) else {
            print("[DOWNLOAD] Invalid task description or index in didReceive data.")
            return
        }

        if segmentDataMap[index] == nil {
            segmentDataMap[index] = Data()
        }
        segmentDataMap[index]?.append(data)
    }

    // MARK: URLSessionTaskDelegate

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        defer { lock.unlock() }

        guard let taskDesc = task.taskDescription, let index = Int(taskDesc) else {
            print("[DOWNLOAD] didCompleteWithError called with invalid task description.")
            finishWithError(NSError(domain: "InvalidTaskDescription", code: -1, userInfo: nil))
            return
        }

        if let error = error {
            print("[DOWNLOAD] Segment task \(index) failed: \(error.localizedDescription)")
            finishWithError(error)
            return
        }

        print("[DOWNLOAD] Segment task \(index) completed successfully.")
        let segmentFile = segmentsDir.appendingPathComponent("segment-\(index)")
        guard let segmentData = segmentDataMap[index], !segmentData.isEmpty else {
            print("[DOWNLOAD] No data for segment \(index), treating as failure.")
            finishWithError(NSError(domain: "SegmentDataNil", code: -1, userInfo: nil))
            return
        }

        do {
            try segmentData.write(to: segmentFile, options: .atomic)
            print("[DOWNLOAD] Wrote segment \(index) to disk: \(segmentFile.lastPathComponent)")
        } catch {
            print("[DOWNLOAD] Failed to write segment \(index) data: \(error.localizedDescription)")
            finishWithError(error)
            return
        }

        segmentDataMap.removeValue(forKey: index)
        runningTasks -= 1
        completedSegments += 1 // increment the completed segment count
        
        // Print progress
        let progress = Double(completedSegments) / Double(totalTasks) * 100.0
        print(String(format: "[DOWNLOAD] Progress: %.2f%% (%d/%d segments)", progress, completedSegments, totalTasks))

        // Start next if available
        if !segmentQueue.isEmpty && !finished {
            startNextSegmentsIfPossible()
        }

        if runningTasks == 0 && segmentQueue.isEmpty && !finished {
            print("[DOWNLOAD] All segments completed successfully.")
            finishSuccessfully()
        }
    }

    private func finishWithError(_ error: Error) {
        if finished { return }
        finished = true
        cleanup()
        DispatchQueue.main.async {
            self.completionHandler(.failure(error))
        }
    }

    private func finishSuccessfully() {
        if finished { return }
        finished = true
        cleanup()
        DispatchQueue.main.async {
            self.completionHandler(.success(()))
        }
    }

    private func cleanup() {
        print("[DOWNLOAD] Cleaning up download session.")
        session?.invalidateAndCancel()
        session = nil
        segmentDataMap.removeAll()
        segmentQueue.removeAll()
    }
}
