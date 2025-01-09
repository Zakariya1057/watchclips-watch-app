import SwiftUI
import Combine

/// The status of a locally tracked download
enum DownloadStatus: String, Codable {
    case notStarted
    case downloading
    case paused
    case error
    case completed
}

/// A single item that the user can download, bridging your `Video` model with local download info.
struct DownloadedVideo: Identifiable, Codable {
    // Original server video metadata
    var video: Video

    // Our local tracking properties:
    var downloadStatus: DownloadStatus
    var downloadedBytes: Int64
    var totalBytes: Int64

    /// If there's an error, we'll store a message here to display in the UI
    var errorMessage: String?

    var lastDownloadURL: URL?
    
    // Conform to Identifiable by forwarding the `video.id`
    var id: String { video.id }
}
