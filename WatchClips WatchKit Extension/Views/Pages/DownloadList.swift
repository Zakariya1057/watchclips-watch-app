import SwiftUI

struct DownloadList: View {
    @StateObject private var viewModel: DownloadsViewModel

    /// Alert shown if user tries to download but the video is still post-processing
    @State private var showProcessingAlert = false

    /// Used to present the fullScreenCover with a playable video
    @State private var selectedVideo: Video?

    let code: String

    init(code: String) {
        let videosService = VideosService(client: supabase) // adapt as needed
        let cachedService = CachedVideosService(videosService: videosService)
        
        _viewModel = StateObject(
            wrappedValue: DownloadsViewModel(cachedVideosService: cachedService)
        )
        
        self.code = code
    }

    var body: some View {
        VStack {
            // 1) Loading or Error states
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
                // 2) Actual list of downloads
                List {
                    ForEach(viewModel.videos) { item in
                        // Wrap the entire row in a Button so we get highlight feedback
                        Button {
                            // Handle row tap:
                            // If fully downloaded, present player
                            if item.downloadStatus == .completed {
                                selectedVideo = item.video
                            }
                            // If not ready, show alert
                            else if item.video.status != .postProcessingSuccess {
                                showProcessingAlert = true
                            }
                            // Otherwise, user can press sub-buttons (Pause / Download)
                            // so we do nothing here in that scenario.
                        } label: {
                            // The row content
                            DownloadRow(
                                video: item,
                                progress: viewModel.progress(for: item),
                                isFullyDownloaded: viewModel.isFullyDownloaded(item),
                                startOrResumeAction: {
                                    viewModel.startOrResumeDownload(item)
                                },
                                pauseAction: {
                                    viewModel.pauseDownload(item)
                                },
                                deleteAction: {
                                    viewModel.deleteVideo(item)
                                },
                                onProcessingNeeded: {
                                    showProcessingAlert = true
                                }
                            )
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteVideo(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        // Use a "plain" style so it doesn't look like a default button.
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear {
            // Load local from UserDefaults
            viewModel.loadLocalDownloads()

            // Attempt to resume any in-progress downloads
            viewModel.resumeInProgressDownloads()

            // Fetch fresh server videos
            Task {
                await viewModel.loadServerVideos(forCode: code, useCache: false)
            }
        }
        // Present the player in full screen for a fully downloaded video
        .fullScreenCover(item: $selectedVideo) { video in
            VideoPlayerView(code: video.code, videoId: video.id)
                .ignoresSafeArea()
        }
        // Alert if the user tries to download/play a video that's still processing
        .alert("Video Not Ready", isPresented: $showProcessingAlert) {
            Button("OK", role: .cancel) {
                Task {
                    await viewModel.loadServerVideos(forCode: code, useCache: false)
                }
            }
        } message: {
            Text("We’re still optimizing this video for Apple Watch. Please try downloading again soon.")
        }
    }
}
