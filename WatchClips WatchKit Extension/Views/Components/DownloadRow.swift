import SwiftUI

struct DownloadRow: View {
    // MARK: - Inputs
    let video: DownloadedVideo
    let progress: Double   // 0..1
    let isFullyDownloaded: Bool
    
    /// **NEW**: whether we're currently offline
    let isOffline: Bool

    let startOrResumeAction: () -> Void
    let pauseAction: () -> Void
    let deleteAction: () -> Void
    let onProcessingNeeded: () -> Void

    // MARK: - Private Computed Properties
    private let downloadedBytes: Int64
    private let totalBytes: Int64
    private let fileSize: Int64

    private let downloadedStr: String
    private let totalStr: String
    private let fileSizeStr: String

    init(
        video: DownloadedVideo,
        progress: Double,
        isFullyDownloaded: Bool,
        /// **NEW**: add `isOffline` to the initializer
        isOffline: Bool,
        startOrResumeAction: @escaping () -> Void,
        pauseAction: @escaping () -> Void,
        deleteAction: @escaping () -> Void,
        onProcessingNeeded: @escaping () -> Void
    ) {
        self.video = video
        self.progress = progress
        self.isFullyDownloaded = isFullyDownloaded
        self.isOffline = isOffline
        self.startOrResumeAction = startOrResumeAction
        self.pauseAction = pauseAction
        self.deleteAction = deleteAction
        self.onProcessingNeeded = onProcessingNeeded

        // Pre-calc repeated values
        downloadedBytes = video.downloadedBytes
        totalBytes      = video.totalBytes
        fileSize        = video.video.size ?? 0

        downloadedStr   = formattedFileSize(downloadedBytes)
        totalStr        = formattedFileSize(totalBytes)
        fileSizeStr     = formattedFileSize(fileSize)
    }

    var body: some View {
        Button {
            handleRowTap()
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    DownloadRowHeader(
                        video: video,
                        totalStr: totalStr,
                        statusText: statusText
                    )

                    // Show progress if actively downloading
                    if video.downloadStatus == .downloading {
                        ProgressView(value: progress)
                            .frame(maxWidth: .infinity)
                            .animation(nil, value: progress) // turn off default animation
                    }

                    // Show partial or total file-size info
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

                    // Error
                    if video.downloadStatus == .error {
                        Text("Error: \(video.errorMessage ?? "Unknown")")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }

                    // Processing or action buttons
                    if video.video.status != .postProcessingSuccess {
                        Button("Processing...") { }
                            .disabled(true)
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                    } else {
                        // Pass `isOffline` into the actions
                        DownloadRowActions(
                            video: video,
                            isFullyDownloaded: isFullyDownloaded,
                            progress: progress,
                            isOffline: isOffline,            // <--- pass the offline state here
                            startOrResumeAction: startOrResumeAction,
                            pauseAction: pauseAction,
                            onProcessingNeeded: onProcessingNeeded
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .transaction { transaction in
            transaction.animation = nil // disable implicit row animations
        }
    }

    // MARK: - Private Handlers
    private func handleRowTap() {
        switch video.downloadStatus {
        case .completed:
            // Possibly present the player
            break
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
            Text("Downloaded").foregroundColor(.green)
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

/// Subview for the action buttons: Download, Pause, etc.
fileprivate struct DownloadRowActions: View {
    let video: DownloadedVideo
    let isFullyDownloaded: Bool
    let progress: Double
    
    /// **NEW**: Offline state
    let isOffline: Bool

    let startOrResumeAction: () -> Void
    let pauseAction: () -> Void
    let onProcessingNeeded: () -> Void

    var body: some View {
        Group {
            switch video.downloadStatus {
            case .completed:
                // Nothing to show if fully downloaded
                EmptyView()

            case .downloading:
                Button("Pause") {
                    pauseAction()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

            case .error, .paused, .notStarted:
                if !isFullyDownloaded {
                    // If OFFLINE, show a disabled "Offline" button
                    if isOffline {
                        Button("Offline") {}
                            .disabled(true)
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    } else {
                        // Normal "Download" button
                        Button("Download") {
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
        }
        .padding(.vertical, 5)
        // Disable default animations so the row won't jump around
        .animation(nil, value: video.downloadStatus)
        .animation(nil, value: progress)
    }
}
