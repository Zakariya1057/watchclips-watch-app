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
                // Show a loading row
                HStack {
                    ProgressView("Loading videos...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                }
                .listRowBackground(Color.black)
            }
            
            if viewModel.videos.isEmpty {
                if let error = viewModel.errorMessage {
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
            }
            else {
                // 2) Actual list of downloads
                List {
                    ForEach(viewModel.videos) { item in
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
                                viewModel.deleteVideo(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    Task {
                        await viewModel.loadServerVideos(forCode: code, useCache: false)
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
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
                await viewModel.loadServerVideos(forCode: code, useCache: true)
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
