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
            
            // 1) Loading / Empty states...
            if sharedVM.videos.isEmpty {
                
                // Show progress if loading
                if sharedVM.isLoading {
                    HStack {
                        ProgressView("Loading videos...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding()
                    }
                }
                
                // If there's an error, show it...
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
                
                // 2) Main List of videos...
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
                    // If not, do: ForEach(sharedVM.videos, id: \.someUniqueField) { vid in
                    ForEach(sharedVM.videos, id: \.id) { vid in
                        
                        // Convert to "DownloadedVideo"
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
                        .onTapGesture {
                            // Attempt to play if downloaded
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
                .listStyle(.plain) // Plain list style can reduce some layout quirks
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
                    // Optionally remove animation
                    // withAnimation(.none) {
                    Task {
                        await sharedVM.refreshVideos(code: code, forceRefresh: true)
                    }
                    // }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                // Only trigger if needed
                DispatchQueue.main.async {
                    downloadsVM.onAppearCheckForURLChanges()
                }
            }
        }
        .onAppear {
            // Let the view fully appear, then check for changes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
                    // force a refresh to see if video has finished processing
                    await sharedVM.refreshVideos(code: code, forceRefresh: true)
                }
            }
        } message: {
            Text("We’re still optimizing this video for Apple Watch. Please try again soon.")
        }
    }
}
