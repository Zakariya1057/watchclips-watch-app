import SwiftUI

struct DownloadList: View {
    @EnvironmentObject var downloadsVM: DownloadsViewModel
    @EnvironmentObject var sharedVM: SharedVideosViewModel
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var showProcessingAlert = false
    @State private var selectedVideo: Video?
    
    // Decouple "loading too long" indicator from `sharedVM.isLoading`
    @State private var showLoadingIndicator = false
    @State private var loadingDelayTask: Task<Void, Never>? = nil

    let code: String
    
    // Removed the local isMonitoringProcessing/checkProcessingTask/state & helper methods
    // to move them into the DownloadsViewModel

    init(code: String) {
        self.code = code
    }
    
    var body: some View {
        VStack {
            if sharedVM.videos.isEmpty {
                if showLoadingIndicator {
                    loadingView
                }
                
                if let error = sharedVM.errorMessage {
                    Text("Failed or no videos: \(error)")
                }
                else if !sharedVM.isLoading && !showLoadingIndicator {
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
                if showLoadingIndicator {
                    loadingView
                }
                
                // Main list of videos
                List {
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
                                    selectedVideo = downloadedVideo.video
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
                .transaction { transaction in
                    // Disable implicit row animations
                    transaction.animation = nil
                }
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
                        downloadsVM.onAppearCheckForURLChanges()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        // Monitor .isLoading changes in sharedVM
        .onChange(of: sharedVM.isLoading) { newValue in
            if newValue {
                loadingDelayTask?.cancel()
                loadingDelayTask = Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
                    if !Task.isCancelled && sharedVM.isLoading {
                        showLoadingIndicator = true
                    }
                }
            } else {
                loadingDelayTask?.cancel()
                showLoadingIndicator = false
            }
        }
        // On scene becoming active, refresh
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                Task {
                    await sharedVM.refreshVideos(code: code, forceRefresh: true)
                    downloadsVM.onAppearCheckForURLChanges()
                }
            }
        }
        // On appear => do initial refresh and start the new processing checker from VM
        .onAppear {
            Task {
                await sharedVM.refreshVideos(code: code, forceRefresh: true)
                downloadsVM.onAppearCheckForURLChanges()
            }
        }
        // Hide default nav back button
        .navigationBarBackButtonHidden(true)
        
        // Full-Screen Video Playback
        .fullScreenCover(item: $selectedVideo) { video in
            VideoPlayerView(code: video.code, videoId: video.id, filename: video.filename)
                .ignoresSafeArea()
        }
        
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
    
    /// Loading spinner + extra text to reassure the user
    private var loadingView: some View {
        HStack {
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.4)
                
                Text("Loading videos...")
                    .font(.headline)
                
                Text("It's taking a bit of time.\nPlease be patient.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .padding()
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
