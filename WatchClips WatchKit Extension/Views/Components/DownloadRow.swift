import SwiftUI

struct DownloadRow: View {
    let video: DownloadedVideo
    let progress: Double   // 0..1
    let isFullyDownloaded: Bool

    let startOrResumeAction: () -> Void
    let pauseAction: () -> Void
    let deleteAction: () -> Void
    let onProcessingNeeded: () -> Void

    var body: some View {
        Button {
            // Tapped anywhere on the row
            if video.downloadStatus == .completed {
                // Possibly present the player or set `selectedVideo` in parent
                // We'll do that in the parent’s .onTapGesture or by returning an event
            } else if video.video.status != .postProcessingSuccess {
                onProcessingNeeded()
            }
            // else if it's not downloaded => do nothing (the internal "Download" button can handle that)
        } label: {
            // The row's visual content
            HStack(alignment: .top) {
                let downloadedBytes = video.downloadedBytes
                let totalBytes = video.totalBytes
                let fileSize = video.video.size ?? 0

                let downloadedStr = formattedFileSize(downloadedBytes)
                let totalStr      = formattedFileSize(totalBytes)
                let fileSizeStr   = formattedFileSize(fileSize)

                VStack(alignment: .leading, spacing: 6) {
                    Text(video.video.title ?? "Untitled")
                        .font(.headline)
                        .lineLimit(1)

                    statusText
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if video.downloadStatus == .downloading {
                        ProgressView(value: progress)
                            .frame(maxWidth: .infinity)
                    }

                    // Show partial bytes if we have them
                    if video.downloadStatus != .completed {
                        if downloadedBytes > 0 && totalBytes > 0,
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

                    // Show error if any
                    if video.downloadStatus == .error {
                        Text("Error: \(video.errorMessage ?? "Unknown")")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }

                    if video.video.status != .postProcessingSuccess {
                        Button("Processing...") {}
                        .disabled(true)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    } else {
                        // Secondary action buttons
                        Group {
                            switch video.downloadStatus {
                            case .completed:
                                EmptyView()

                            case .downloading:
                                // Pause
                                Button("Pause") {
                                    pauseAction()
                                }
                                .buttonStyle(.borderedProminent)
                                .frame(maxWidth: .infinity)

                            case .error, .paused, .notStarted:
                                if !isFullyDownloaded {
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
                        .padding(.vertical, 5)
                    }

                }

                Spacer()

                // If fully downloaded, show checkmark + total size
                VStack(alignment: .trailing) {
                    if video.downloadStatus == .completed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 20))
                            .padding(.trailing, 5)

                        Spacer()

                        Text(totalStr)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

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

    /// Converts bytes to "XXX.X MB" or "YYY.Y KB"
    private func formattedFileSize(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024.0 {
            // Show in KB
            return String(format: "%.1f KB", kb)
        } else {
            // Show in MB
            let mb = kb / 1024.0
            return String(format: "%.1f MB", mb)
        }
    }
}
