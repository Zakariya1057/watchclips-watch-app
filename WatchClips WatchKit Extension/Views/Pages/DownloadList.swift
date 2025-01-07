//
//  DownloadList.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//

import SwiftUI

struct DownloadList: View {
    @EnvironmentObject var downloadsVM: DownloadsViewModel
    @EnvironmentObject var sharedVM: SharedVideosViewModel
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var showProcessingAlert = false
    @State private var selectedVideo: Video?

    let code: String
    
    init(code: String) {
        self.code = code
    }

    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        VStack {
            // If you want the user to see an updated sharedVM.videos list:
            if sharedVM.isLoading {
                HStack {
                    ProgressView("Loading videos...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                }
                .listRowBackground(Color.black)
            }
            
            if sharedVM.videos.isEmpty {
                if let error = sharedVM.errorMessage {
                    Text("Failed or no videos: \(error)")
                } else {
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
                // Show the server's videos from sharedVM
                List {
                    ForEach(sharedVM.videos) { vid in
                        // Convert to DownloadedVideo if we have a local record
                        let downloadedVideo: DownloadedVideo = downloadsVM.itemFor(video: vid)
                        
                        DownloadRow(
                            video: downloadedVideo,
                            progress: downloadsVM.progress(for: downloadedVideo),
                            isFullyDownloaded: downloadsVM.isFullyDownloaded(downloadedVideo),
                            startOrResumeAction: {
                                // If it's still post-processing, show alert
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
                            }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if downloadedVideo.downloadStatus == .completed {
                                selectedVideo = downloadedVideo.video
                            } else if downloadedVideo.video.status != .postProcessingSuccess {
                                showProcessingAlert = true
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                downloadsVM.deleteVideo(downloadedVideo)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                // Now call the SHARED VM refresh
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
                // If you want to recheck any partial downloads, etc.
                downloadsVM.onAppearCheckForURLChanges()
            }
        }
        .onAppear {
            downloadsVM.onAppearCheckForURLChanges()
        }
        .navigationBarBackButtonHidden(true)
        .fullScreenCover(item: $selectedVideo) { video in
            VideoPlayerView(code: video.code, videoId: video.id, filename: video.filename)
                .ignoresSafeArea()
        }
        .alert("Video Not Ready", isPresented: $showProcessingAlert) {
            Button("OK", role: .cancel) {
                // Attempt a refresh if you want
                Task {
                    await sharedVM.refreshVideos(code: code, forceRefresh: true)
                }
            }
        } message: {
            Text("We’re still optimizing this video for Apple Watch. Please try again soon.")
        }
    }
}
