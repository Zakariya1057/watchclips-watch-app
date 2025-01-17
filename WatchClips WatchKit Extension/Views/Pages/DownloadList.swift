import SwiftUI

struct DownloadList: View {
    @EnvironmentObject var downloadsVM: DownloadsViewModel
    @EnvironmentObject var sharedVM: SharedVideosViewModel
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var showProcessingAlert = false
    
    @State private var showLoadingOverlay = false
    @State private var isLongWait = false
    @State private var loadingDelayTask: Task<Void, Never>? = nil
    
    @StateObject private var appState = AppState.shared
    
    let code: String
    
    init(code: String) {
        self.code = code
    }
    
    var body: some View {
        VStack {
            if showLoadingOverlay {
                LoadingOverlayView(isLongWait: isLongWait, hideSpinner: false)
            }
            
            if sharedVM.videos.isEmpty {
                if sharedVM.isOffline {
                    OfflineBannerView()
                }
                
                // Show error or empty state otherwise
                if let error = sharedVM.errorMessage {
                    Text("Failed or no videos: \(error)")
                } else if !sharedVM.isLoading && !showLoadingOverlay {
                    VStack(spacing: 16) {
                        Text("No Videos Found")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Go on WatchClips.app and upload some videos to download here.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                }
            } else {
                List {
                    if sharedVM.isOffline {
                        OfflineBannerView()
                    }
                    
                    ForEach(sharedVM.videos, id: \.id) { vid in
                        let downloadedVideo = downloadsVM.itemFor(video: vid)
                        
                        DownloadRowContainer(
                            downloadedVideo: downloadedVideo,
                            isOffline: sharedVM.isOffline,
                            startOrResumeAction: {
                                if downloadedVideo.video.status != .postProcessingSuccess {
                                    showProcessingAlert = true
                                } else {
                                    downloadsVM.startOrResumeDownload(downloadedVideo)
                                }
                            },
                            pauseAction: {
                                downloadsVM.pauseDownload(downloadedVideo)
                            },
                            deleteAction: {
                                downloadsVM.deleteVideo(downloadedVideo)
                            },
                            onProcessingNeeded: {
                                showProcessingAlert = true
                            },
                            onSelectedForPlayback: {
                                print("Play Video")
                                // Attempt to play if downloaded
                                if downloadedVideo.downloadStatus == .completed {
                                    appState.selectedVideo = downloadedVideo.video
                                } else if downloadedVideo.video.status != .postProcessingSuccess {
                                    showProcessingAlert = true
                                }
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                downloadsVM.deleteVideo(downloadedVideo)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            // Leading "Back" button
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
            // Refresh button
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await sharedVM.refreshVideos(code: code, forceRefresh: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        // Observe .isLoading changes to drive our custom two-step loading overlay
        .onChange(of: sharedVM.isLoading) { newValue in
            if newValue {
                // Immediately show "Loading videos..."
                showLoadingOverlay = true
                isLongWait = false
                
                // Cancel any existing delay task
                loadingDelayTask?.cancel()
                
                // After 2 seconds, if still loading, switch text to "Sorry for the wait..."
                loadingDelayTask = Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if !Task.isCancelled && sharedVM.isLoading {
                        isLongWait = true
                    }
                }
            } else {
                // Done loading => reset overlay state
                showLoadingOverlay = false
                isLongWait = false
                loadingDelayTask?.cancel()
            }
        }
        // Hide default nav back button
        .navigationBarBackButtonHidden(true)
        
        // “Video Not Ready” Alert
        .alert("Video Not Ready", isPresented: $showProcessingAlert) {
            Button("OK", role: .cancel) {
                Task {
                    await sharedVM.refreshVideos(code: code, forceRefresh: true)
                }
            }
        } message: {
            Text("We’re still optimizing this video for Apple Watch. Please try again soon.")
        }
    }
}

/// Container for each row, unchanged
fileprivate struct DownloadRowContainer: View {
    let downloadedVideo: DownloadedVideo
    
    let isOffline: Bool
    let startOrResumeAction: () -> Void
    let pauseAction: () -> Void
    let deleteAction: () -> Void
    let onProcessingNeeded: () -> Void
    let onSelectedForPlayback: () -> Void
    
    @EnvironmentObject var downloadsVM: DownloadsViewModel
    
    var body: some View {
        DownloadRow(
            video: downloadedVideo,
            progress: downloadsVM.progress(for: downloadedVideo),
            isFullyDownloaded: downloadsVM.isFullyDownloaded(downloadedVideo),
            isOffline: isOffline,
            startOrResumeAction: startOrResumeAction,
            pauseAction: pauseAction,
            deleteAction: deleteAction,
            onProcessingNeeded: onProcessingNeeded,
            onSelectedForPlayback: onSelectedForPlayback
        )
    }
}
