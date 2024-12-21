import SwiftUI
import Supabase
import Network

struct VideoListView: View {
    let code: String
    
    @State private var videos: [Video] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @AppStorage("loggedInCode") private var loggedInCode: String = ""
    @State private var showLogoutConfirmation = false
    @State private var isOffline = false
    @State private var isDeletingAll = false
    @StateObject private var networkMonitor = NetworkMonitor()
    @State private var isInitialLoad = true
    
    @State private var showProcessingAlert = false
    @State private var selectedVideo: Video? // Now used as an item for fullScreenCover
    
    private var videosService: VideosService {
        VideosService(client: supabase)
    }
    
    private var cachedVideosService: CachedVideosService {
        CachedVideosService(videosService: videosService)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 2) EXISTING ZSTACK + CONTENT
                ZStack {
                    content
                        .ignoresSafeArea(.all, edges: [.horizontal])
                    
                    if isDeletingAll {
                        // Overlay while deleting videos
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView("Deleting videos...")
                                .progressViewStyle(CircularProgressViewStyle())
                                .padding()
                            Text("Please wait while we remove all downloaded content.")
                                .font(.footnote)
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                    }
                }
                .onAppear {
                    loadVideos()
                }
                .onReceive(networkMonitor.$isConnected) { isConnected in
                    if isConnected && isOffline && !isInitialLoad {
                        Task {
                            await handleRefresh()
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Code: " + loggedInCode)
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        Task {
                            await handleRefresh(forceRefresh: true)
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
            .alert("Confirm Logout", isPresented: $showLogoutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Logout", role: .destructive) {
                    Task {
                        await deleteAllVideosAndLogout()
                    }
                }
            } message: {
                Text("This will also delete all downloaded videos. Are you sure you want to log out?")
            }
            .alert("Processing...", isPresented: $showProcessingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Optimizing video for Apple Watch. Please wait...")
            }
            // Use the item version of fullScreenCover so that selectedVideo is guaranteed not nil
            .fullScreenCover(item: $selectedVideo) { video in
                VideoPlayerView(code: video.code, videoId: video.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading videos...")
                .progressViewStyle(CircularProgressViewStyle())
                .padding()
        } else {
            if videos.isEmpty {
                emptyOrErrorStateView
            } else {
                videoListView
            }
        }
    }
    
    @ViewBuilder
    private var emptyOrErrorStateView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "video.slash.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.gray.opacity(0.8))

                if let error = errorMessage {
                    Text("Failed to load videos")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Retry") {
                        Task {
                            await handleRefresh(forceRefresh: true)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    
                } else {
                    Text("No Videos Found")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Go on WatchClips.app and upload some videos to watch here.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                logoutButton
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
    
    private var videoListView: some View {
        List {
            Section {
                NavigationLink(destination: DownloadList(code: code)) {
                    Text("Downloads")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            
            if isOffline {
                HStack(spacing: 4) {
                    Image(systemName: "wifi.slash")
                        .font(.caption2)
                    Text("Offline - Showing Cached Videos")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            // Ensure Video is Identifiable and provide a stable id
            ForEach(videos) { video in
                VideoRow(video: video)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if (video.status == .postProcessingSuccess) {
                            selectedVideo = video
                        } else {
                            showProcessingAlert = true
                        }

                    }
                    .listRowBackground(Color(.black))
                    .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10))
            }
            .onDelete(perform: deleteVideo)

            logoutButton
        }
    }

    private func deleteVideo(at offsets: IndexSet) {
        Task {
            if let index = offsets.first {
                let video = videos[index]
                do {
                    try await videosService.deleteVideo(withId: video.id)
                    cachedVideosService.removeFromCache(id: video.id)
                    VideoDownloadManager.shared.deleteVideoFor(code: video.code, videoId: video.id)
                    await handleRefresh(forceRefresh: false)
                } catch {
                    await MainActor.run {
                        print(error)
                        errorMessage = error.localizedDescription
                        showErrorAlert = true
                    }
                }
            }
        }
    }
    
    private func handleRefresh(forceRefresh: Bool = true) async {
        await MainActor.run {
            errorMessage = nil
            isLoading = true
        }
        let oldVideos = videos
        defer {
            Task { @MainActor in isLoading = false }
        }

        do {
            let fetchedVideos = try await (forceRefresh
                                           ? cachedVideosService.refreshVideos(forCode: code)
                                           : cachedVideosService.fetchVideos(forCode: code, useCache: true))
            
            let fetchedIDs = Set(fetchedVideos.map { $0.id })
            let missingVideos = oldVideos.filter { !fetchedIDs.contains($0.id) }

            await MainActor.run {
                videos = fetchedVideos
                isOffline = false
                errorMessage = nil
                isInitialLoad = false
            }
            
            for missingVid in missingVideos {
                VideoDownloadManager.shared.deleteVideoFor(code: missingVid.code, videoId: missingVid.id)
            }
        } catch {
            let cached = loadCachedVideos()
            await MainActor.run {
                if let cached = cached, !cached.isEmpty {
                    videos = cached
                    isOffline = true
                    errorMessage = error.localizedDescription
                } else {
                    videos = []
                    errorMessage = error.localizedDescription
                    isOffline = true
                }
                isInitialLoad = false
            }
        }
    }
    
    private func loadCachedVideos() -> [Video]? {
        return cachedVideosService.loadCachedVideos()
    }

    private var logoutButton: some View {
        Section {
            Button(action: {
                showLogoutConfirmation = true
            }) {
                Text("Logout")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .cornerRadius(8)
            }
            .padding()
        }
    }

    private func loadVideos() {
        Task {
            await MainActor.run {
                isLoading = true
                errorMessage = nil
            }
            defer {
                Task { @MainActor in isLoading = false }
            }
            
            do {
                let fetchedVideos = try await cachedVideosService.fetchVideos(forCode: code, useCache: true)
                await MainActor.run {
                    videos = fetchedVideos
                    isOffline = false
                    errorMessage = nil
                    isInitialLoad = false
                }
            } catch {
                let cached = loadCachedVideos()
                await MainActor.run {
                    if let cached = cached, !cached.isEmpty {
                        videos = cached
                        isOffline = true
                        errorMessage = error.localizedDescription
                    } else {
                        videos = []
                        isOffline = true
                        errorMessage = error.localizedDescription
                    }
                    isInitialLoad = false
                }
            }
        }
    }
    
    private func deleteAllVideosAndLogout() async {
        await MainActor.run {
            isDeletingAll = true
        }

        await MainActor.run {
            loggedInCode = ""
        }

        Task.detached {
            VideoDownloadManager.shared.deleteAllSavedVideos()
        }

        await MainActor.run {
            isDeletingAll = false
        }
    }
}
