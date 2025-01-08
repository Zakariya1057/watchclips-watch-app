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
    
    let code: String
    
    init(code: String) {
        self.code = code
    }
    
    var body: some View {
        VStack {
            if sharedVM.videos.isEmpty {
                
                // 1) Loading / Empty states...
                if sharedVM.isLoading {
                    HStack {
                        ProgressView("Loading videos...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding()
                    }
                }
                
                if let error = sharedVM.errorMessage {
                    Text("Failed or no videos: \(error)")
                } else if !sharedVM.isLoading {
                    // Only show "No Videos Found" if not loading
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
                
                // 2) Main List of videos
                List {
                    // Show top-of-list progress if still loading more
                    if sharedVM.isLoading {
                        HStack {
                            ProgressView("Loading videos...")
                                .progressViewStyle(CircularProgressViewStyle())
                                .padding()
                        }
                    }
                    
                    // IMPORTANT: Make sure Video is Identifiable
                    ForEach(sharedVM.videos, id: \.id) { vid in
                        // Convert to "DownloadedVideo"
                        let downloadedVideo = downloadsVM.itemFor(video: vid)
                        
                        DownloadRowContainer(
                            downloadedVideo: downloadedVideo,
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
                // Disable implicit animations that can cause re-layout or slow performance with large data
                .transaction { transaction in
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
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                Task {
                    downloadsVM.onAppearCheckForURLChanges()
                }
            }
        }
        .onAppear {
            // Let the view fully appear, then check for changes
            Task {
                downloadsVM.onAppearCheckForURLChanges()
            }
        }
        .navigationBarBackButtonHidden(true)
        
        // 3) Full-Screen Video Playback
        .fullScreenCover(item: $selectedVideo) { video in
            VideoPlayerView(code: video.code, videoId: video.id, filename: video.filename)
                .ignoresSafeArea()
        }
        
        // 4) “Video Not Ready” Alert
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
}

fileprivate struct DownloadRowContainer: View {
    let downloadedVideo: DownloadedVideo
    
    let startOrResumeAction: () -> Void
    let pauseAction: () -> Void
    let deleteAction: () -> Void
    let onProcessingNeeded: () -> Void
    let onSelectedForPlayback: () -> Void
    
    @EnvironmentObject var downloadsVM: DownloadsViewModel
    
    var body: some View {
        // “DownloadRow” logic extracted into a container
        // to reduce repeated layout calculations & re-renders.
        //
        // This helps SwiftUI track the row’s identity more efficiently.
        DownloadRow(
            video: downloadedVideo,
            progress: downloadsVM.progress(for: downloadedVideo),
            isFullyDownloaded: downloadsVM.isFullyDownloaded(downloadedVideo),
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
