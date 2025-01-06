import SwiftUI

struct DownloadList: View {
    /// Instead of creating a new DownloadsdownloadsVM,
    /// we rely on the parent to provide it as an environment object.
    @EnvironmentObject var downloadsVM: DownloadsViewModel
    @EnvironmentObject var videosService: VideosService
    
    @Environment(\.dismiss) private var dismiss
    
    /// Alert shown if user tries to download but the video is still post-processing
    @State private var showProcessingAlert = false

    /// Used to present the fullScreenCover with a playable video
    @State private var selectedVideo: Video?

    let code: String

    /// Simple init that just stores the code.
    /// We no longer create a new `DownloadsdownloadsVM` here.
    init(code: String) {
        self.code = code
    }

    var body: some View {
        VStack {
            // 1) Loading or Error states
            if downloadsVM.isLoading {
                HStack {
                    ProgressView("Loading videos...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                }
                .listRowBackground(Color.black)
            }
            
            if downloadsVM.videos.isEmpty {
                if let error = downloadsVM.errorMessage {
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
                // 2) Actual list of downloads
                List {
                    ForEach(downloadsVM.videos) { item in
                        DownloadRow(
                            video: item,
                            progress: downloadsVM.progress(for: item),
                            isFullyDownloaded: downloadsVM.isFullyDownloaded(item),
                            startOrResumeAction: {
                                downloadsVM.startOrResumeDownload(item)
                            },
                            pauseAction: {
                                downloadsVM.pauseDownload(item)
                            },
                            deleteAction: {
                                downloadsVM.deleteVideo(item)
                            },
                            onProcessingNeeded: {
                                showProcessingAlert = true
                            }
                        )
                        .contentShape(Rectangle()) // Ensures the entire row is tappable
                        .onTapGesture {
                            if item.downloadStatus == .completed {
                                selectedVideo = item.video
                            } else if item.video.status != .postProcessingSuccess {
                                showProcessingAlert = true
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                downloadsVM.deleteVideo(item)
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
                Button {
                    Task {
                        await downloadsVM.loadServerVideos(forCode: code, useCache: false)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            // Only fetch fresh server videos.
            // If you also want local/resume logic,
            // call `downloadsVM.loadLocalDownloads()` etc. here as well.
            Task {
                await downloadsVM.loadServerVideos(forCode: code, useCache: false)
                downloadsVM.onAppearCheckForURLChanges()
            }
        }
        .navigationBarBackButtonHidden(true)
        // Present the player in full screen for a fully downloaded video
        .fullScreenCover(item: $selectedVideo) { video in
            VideoPlayerView(code: video.code, videoId: video.id, filename: video.filename)
                .ignoresSafeArea()
        }
        // Alert if the user tries to download/play a video that's still processing
        .alert("Video Not Ready", isPresented: $showProcessingAlert) {
            Button("OK", role: .cancel) {
                Task {
                    await downloadsVM.loadServerVideos(forCode: code, useCache: false)
                }
            }
        } message: {
            Text("We’re still optimizing this video for Apple Watch. Please try downloading again soon.")
        }
    }
}
