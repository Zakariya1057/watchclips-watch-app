//
//  DownloadList.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//  Optimized on 08/01/2025 by ChatGPT
//

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
    
    init(code: String) {
        self.code = code
    }
    
    var body: some View {
        VStack {
            if sharedVM.videos.isEmpty {
                // Only show the spinner if we've been loading for more than 1.5 seconds
                if showLoadingIndicator {
                    loadingView
                }
                
                // If there's an error, show it
                if let error = sharedVM.errorMessage {
                    Text("Failed or no videos: \(error)")
                }
                // If no error and not loading, show "No Videos Found"
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
                // If we do have videos, but loading is still ongoing,
                // we can still show the delayed indicator for partial updates if desired
                if showLoadingIndicator {
                    loadingView
                }
                
                // Main list of videos
                List {
                    // IMPORTANT: Make sure Video is Identifiable
                    ForEach(sharedVM.videos, id: \.id) { vid in
                        // Convert to "DownloadedVideo"
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
                // Cancel any existing task so we don’t stack multiple
                loadingDelayTask?.cancel()
                
                // Schedule a new delay for 1.5 seconds
                loadingDelayTask = Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
                    // If still loading, show indicator
                    if !Task.isCancelled && sharedVM.isLoading {
                        showLoadingIndicator = true
                    }
                }
            } else {
                // Loading ended => cancel delay + hide indicator
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
        // On appear, do an initial refresh
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
                    // Force a refresh to see if video has finished processing
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
                
                // Additional reassurance message
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

/// Container that reuses the layout logic for a single row.
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
        // “DownloadRow” logic extracted into a container
        // to reduce repeated layout calculations & re-renders.
        DownloadRow(
            video: downloadedVideo,
            progress: downloadsVM.progress(for: downloadedVideo),
            isFullyDownloaded: downloadsVM.isFullyDownloaded(downloadedVideo),
            isOffline: isOffline,
            startOrResumeAction: startOrResumeAction,
            pauseAction: pauseAction,
            deleteAction: deleteAction,
            onProcessingNeeded: onProcessingNeeded
        )
        .onTapGesture {
            onSelectedForPlayback()
        }
    }
}
