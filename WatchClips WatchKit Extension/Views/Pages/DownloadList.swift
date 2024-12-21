import SwiftUI

struct DownloadList: View {
    @StateObject private var viewModel: DownloadsViewModel
    
    /// Alert shown if user tries to download but the video is still post-processing
    @State private var showProcessingAlert = false
    
    let code: String
    
    init(code: String) {
        let videosService = VideosService(client: supabase) // adapt this as needed
        let cachedService = CachedVideosService(videosService: videosService)
        _viewModel = StateObject(wrappedValue: DownloadsViewModel(cachedVideosService: cachedService))
        self.code = code
    }
    
    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView("Loading videos...")
            }
            else if viewModel.videos.isEmpty {
                if let error = viewModel.errorMessage {
                    Text("Failed or no videos: \(error)")
                } else {
                    Text("No Videos Found for \(code)")
                }
            }
            else {
                List {
                    ForEach(viewModel.videos) { item in
                        DownloadRow(
                            video: item,
                            progress: viewModel.progress(for: item),
                            isFullyDownloaded: viewModel.isFullyDownloaded(item),
                            startOrResumeAction: { viewModel.startOrResumeDownload(item) },
                            pauseAction: { viewModel.pauseDownload(item) },
                            deleteAction: { viewModel.deleteVideo(item) },
                            onProcessingNeeded: {
                                // If the video is still post-processing, show the alert
                                showProcessingAlert = true
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteVideo(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            // Load local from UserDefaults
            viewModel.loadLocalDownloads()
            
            // Attempt to resume any in-progress downloads
            viewModel.resumeInProgressDownloads()
            
            // Optionally fetch server videos from the server
            Task {
                await viewModel.loadServerVideos(forCode: code)
            }
        }
        .alert("Video Not Ready", isPresented: $showProcessingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("We’re still optimizing this video for Apple Watch. Please try downloading again soon.")
        }
    }
}

// MARK: - DownloadRow

struct DownloadRow: View {
    let video: DownloadedVideo
    let progress: Double            // 0..1
    let isFullyDownloaded: Bool
    
    /// Actions that the parent can provide:
    let startOrResumeAction: () -> Void
    let pauseAction: () -> Void
    let deleteAction: () -> Void
    
    /// A new closure that lets us tell the parent view to show the "Processing" alert
    let onProcessingNeeded: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            let downloaded = video.downloadedBytes
            let totalSize = video.totalBytes
            let videoSize = video.video.size ?? 0
            
            let downloadedStr = byteCountFormatter.string(fromByteCount: downloaded)
            let totalStr = byteCountFormatter.string(fromByteCount: totalSize)
            let videoSizeStr = byteCountFormatter.string(fromByteCount: videoSize)
            
            // Left side: Title, status, progress, file size info
            VStack(alignment: .leading, spacing: 6) {
                // Title
                Text(video.video.title ?? "Untitled")
                    .font(.headline)
                    .lineLimit(1)
                
                // Status text & progress
                statusText
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // If actively downloading, show a ProgressView
                if video.downloadStatus == .downloading {
                    ProgressView(value: progress)
                        .frame(maxWidth: .infinity)
                }
                
                // Show "Downloaded MB / Total MB" if known
                if video.downloadStatus != .completed {
                    if downloaded > 0 && totalSize > 0,
                       (video.downloadStatus == .downloading || video.downloadStatus == .paused)
                    {
                        Text("\(downloadedStr) / \(totalStr)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if videoSize > 0 {
                        Text("\(videoSizeStr)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // If there's an error
                if video.downloadStatus == .error {
                    Text("Error: \(video.errorMessage ?? "Unknown")")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
                
                // Buttons
                Group {
                    switch video.downloadStatus {
                    case .completed:
                        // Already downloaded => no button
                        EmptyView()
                        
                    case .downloading:
                        // "Pause" button
                        Button("Pause") {
                            pauseAction()
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        
                    case .error, .paused, .notStarted:
                        // "Download" button
                        if !isFullyDownloaded {
                            Button("Download") {
                                // If the video status is postProcessingSuccess, start the download
                                // otherwise, signal "onProcessingNeeded" to show an alert
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
            
            Spacer()
            
            // If fully downloaded, show checkmark + final file size
            VStack(alignment: .center) {
                if video.downloadStatus == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 20))
                    
                    Spacer()
                    
                    Text(totalStr)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
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
    
    // MARK: - Byte Count Formatter
    
    private var byteCountFormatter: ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter
    }
}
