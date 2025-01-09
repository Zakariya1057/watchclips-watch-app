import SwiftUI
import Combine

struct DownloadRow: View {
    // MARK: - Inputs
    let video: DownloadedVideo
    let progress: Double   // 0..1
    let isFullyDownloaded: Bool
    let isOffline: Bool

    let startOrResumeAction: () -> Void
    let pauseAction: () -> Void
    let deleteAction: () -> Void
    let onProcessingNeeded: () -> Void
    
    /// Called when the user taps the row (completed => playback).
    let onSelectedForPlayback: () -> Void

    // MARK: - Private Computed
    private let downloadedBytes: Int64
    private let totalBytes: Int64
    private let fileSize: Int64

    private let downloadedStr: String
    private let totalStr: String
    private let fileSizeStr: String
    
    // A subtle dark background for the row
    private let rowBackground = Color.black.opacity(0.1)

    init(
        video: DownloadedVideo,
        progress: Double,
        isFullyDownloaded: Bool,
        isOffline: Bool,
        startOrResumeAction: @escaping () -> Void,
        pauseAction: @escaping () -> Void,
        deleteAction: @escaping () -> Void,
        onProcessingNeeded: @escaping () -> Void,
        onSelectedForPlayback: @escaping () -> Void
    ) {
        self.video = video
        self.progress = progress
        self.isFullyDownloaded = isFullyDownloaded
        self.isOffline = isOffline
        self.startOrResumeAction = startOrResumeAction
        self.pauseAction = pauseAction
        self.deleteAction = deleteAction
        self.onProcessingNeeded = onProcessingNeeded
        self.onSelectedForPlayback = onSelectedForPlayback

        // Pre-calc repeated values
        downloadedBytes = video.downloadedBytes
        totalBytes      = video.totalBytes
        fileSize        = video.video.size ?? 0

        downloadedStr   = formattedFileSize(downloadedBytes)
        totalStr        = formattedFileSize(totalBytes)
        fileSizeStr     = formattedFileSize(fileSize)
    }

    var body: some View {
        // Replaces Button with a plain container + onTapGesture
        ZStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    // Header with title + status
                    DownloadRowHeader(
                        video: video,
                        totalStr: totalStr,
                        statusText: statusText
                    )

                    // Show progress if actively downloading
                    if video.downloadStatus == .downloading {
                        ProgressView(value: progress)
                            .frame(maxWidth: .infinity)
                            .animation(nil, value: progress)
                    }

                    // Show partial or total file-size
                    if video.downloadStatus != .completed {
                        if downloadedBytes > 0 && totalBytes > 0 &&
                            (video.downloadStatus == .downloading || video.downloadStatus == .paused) {
                            Text("\(downloadedStr) / \(totalStr)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if fileSize > 0 {
                            Text("\(fileSizeStr)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Show error or optimizing status
                    if video.downloadStatus == .error {
                        Text("Error: \(isOffline ? "No internet connection." : (video.errorMessage ?? "Unknown"))")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    } else if video.downloadStatus == .paused || video.downloadStatus == .notStarted {
                        HStack(spacing: 6) {
                            if video.video.isOptimizing {
                                Image(systemName: "gearshape.2.fill")
                                    .foregroundColor(.yellow)
                                Text("Optimizing…")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            } else {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                Text("Optimized!")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(
                            Capsule()
                                .fill(video.video.isOptimizing
                                      ? Color.yellow.opacity(0.15)
                                      : Color.green.opacity(0.15))
                        )
                        .transition(.opacity)
                    }

                    // If video not done processing, disable real actions
                    if video.video.status != .postProcessingSuccess {
                        Button("Processing...") { }
                            .disabled(true)
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                    } else {
                        // Download/Pause/Resume actions
                        DownloadRowActions(
                            video: video,
                            isFullyDownloaded: isFullyDownloaded,
                            progress: progress,
                            downloadedBytes: downloadedBytes,
                            isOffline: isOffline,
                            startOrResumeAction: startOrResumeAction,
                            pauseAction: pauseAction,
                            onProcessingNeeded: onProcessingNeeded
                        )
                    }
                }
            }
            .padding(.vertical, 8)
            .background(rowBackground)
            .cornerRadius(8)
        }
        // Make the whole ZStack tappable, but not triggered by swipes
        .contentShape(Rectangle())
        .onTapGesture {
            handleRowTap()
        }
        // Turn off default animations
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    // MARK: - Private
    
    private func handleRowTap() {
        // If fully downloaded => playback; else show "Video Not Ready"
        switch video.downloadStatus {
        case .completed:
            onSelectedForPlayback()
        default:
            if video.video.status != .postProcessingSuccess {
                onProcessingNeeded()
            }
        }
    }

    // MARK: - Status Text
    @ViewBuilder
    private var statusText: some View {
        switch video.downloadStatus {
        case .completed:
            Text("Downloaded")
                .foregroundColor(.green)
        case .downloading:
            Text(String(format: "Downloading (%.0f%%)", progress * 100))
                .foregroundColor(.blue)
        case .paused:
            Text(String(format: "Paused (%.0f%%)", progress * 100))
        case .error, .notStarted:
            EmptyView()
        }
    }
}

// MARK: - Subviews

fileprivate struct DownloadRowHeader: View {
    let video: DownloadedVideo
    let totalStr: String
    let statusText: AnyView

    init(video: DownloadedVideo, totalStr: String, statusText: some View) {
        self.video = video
        self.totalStr = totalStr
        self.statusText = AnyView(statusText)
    }

    var body: some View {
        if video.downloadStatus == .completed {
            HStack {
                Text(video.video.title ?? "Untitled")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 20))
                    .padding(.trailing, 5)
            }
            HStack {
                statusText
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(totalStr)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            Text(video.video.title ?? "Untitled")
                .font(.headline)
                .lineLimit(1)

            statusText
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

/// Subview for the download/pause/resume buttons
fileprivate struct DownloadRowActions: View {
    let video: DownloadedVideo
    let isFullyDownloaded: Bool
    let progress: Double
    let downloadedBytes: Int64
    let isOffline: Bool

    let startOrResumeAction: () -> Void
    let pauseAction: () -> Void
    let onProcessingNeeded: () -> Void

    var body: some View {
        Group {
            switch video.downloadStatus {
            case .completed:
                // No action buttons needed
                EmptyView()

            case .downloading:
                Button("Pause") {
                    pauseAction()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

            case .error, .paused, .notStarted:
                if !isFullyDownloaded {
                    Button(downloadedBytes > 0 ? "Resume" : "Download") {
                        if video.video.status == .postProcessingSuccess {
                            startOrResumeAction()
                        } else {
                            onProcessingNeeded()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 5)
        .animation(nil, value: video.downloadStatus)
        .animation(nil, value: progress)
    }
}
