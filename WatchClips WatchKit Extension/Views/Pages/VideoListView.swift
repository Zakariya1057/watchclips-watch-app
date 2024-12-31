//
//  VideoListView.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//

import SwiftUI

struct VideoListView: View {
    // Pull the JSON-encoded loggedInState from AppStorage
    @AppStorage("loggedInState") private var loggedInStateData = Data()
    
    // NEW: Access your userSettingsService from the environment
    @EnvironmentObject private var mainUserSettingsService: UserSettingsService
    
    // NEW: Store the fetched plan in local state
    @State private var plan: Plan?
    
    @State private var videos: [Video] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    @State private var showLogoutConfirmation = false
    @State private var isOffline = false
    @State private var isDeletingAll = false
    @StateObject private var networkMonitor = NetworkMonitor()
    @State private var isInitialLoad = true

    @State private var showProcessingAlert = false
    @State private var selectedVideo: Video? // For fullScreenCover
    
    @StateObject private var notificationManager = NotificationManager.shared
    
    var downloadStore: DownloadsStore = DownloadsStore()
    
    // We can keep these local services for Videos (though you’re also storing them in MyWatchApp)
    private var videosService: VideosService {
        VideosService(client: supabase)
    }
    
    private var cachedVideosService: CachedVideosService {
        CachedVideosService(videosService: videosService)
    }
    
    /// Computed property that extracts the `code` from the loggedInState (if present).
    private var code: String {
        decodeLoggedInState(from: loggedInStateData)?.code ?? ""
    }
    
    /// Old planName from loggedInState (used as fallback or until fresh plan is fetched)
    private var fallbackPlanName: PlanName {
        decodeLoggedInState(from: loggedInStateData)?.planName ?? .free
    }

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    downloadsLink
                    continueWatching
                    
                    if isLoading {
                        loadingRow
                    }
                    
                    if videos.isEmpty && !isLoading {
                        emptyOrErrorStateRows
                    } else {
                        if isOffline {
                            offlineBannerRow
                        }
                        
                        ForEach(videos) { video in
                            VideoRow(
                                video: video,
                                isDownloaded: downloadStore.isDownloaded(videoId: video.id)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Only allow playing if it's fully processed
                                if video.status == .postProcessingSuccess {
                                    selectedVideo = video
                                } else {
                                    showProcessingAlert = true
                                }
                            }
                            // Minimal styling for performance
                            .listRowBackground(Color(.black))
                            .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10))
                        }
                        .onDelete(perform: deleteVideo)
                    }
                    
                    logoutButton
                }
                .listStyle(.plain)
                .onAppear {
                    Task {
                        // Fetch the latest plan, then load videos
                        await fetchPlan()
                        loadVideos()
                    }
                }
                .onReceive(networkMonitor.$isConnected) { isConnected in
                    if isConnected, isOffline, !isInitialLoad {
                        Task {
                            await handleRefresh()
                        }
                    }
                }
                
                if isDeletingAll {
                    deletingOverlay
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Display the freshly fetched plan name if available, else fallback
                    PlanBadgeView(planName: plan?.name ?? fallbackPlanName)
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
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
            .alert("Confirm Logout", isPresented: $showLogoutConfirmation) {
                Button("Cancel", role: .cancel) {}
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
            .fullScreenCover(item: $selectedVideo) { video in
                VideoPlayerView(code: video.code, videoId: video.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
        }
    }
    
    // MARK: - Subviews

    private var downloadsLink: some View {
        NavigationLink(destination: DownloadList(code: code)) {
            HStack(alignment: .center, spacing: 8) {
                Text("Downloads")
                    .font(.headline)
                
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 24, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
        }
        .onAppear {
            notificationManager.requestAuthorization()
        }
    }

    private var continueWatching: some View {
        Group {
            if let resume = plan?.features?.resumeFeature, resume == true {
                // Example: show if there's a resumed video. You could also gate behind plan?.features?.resumeFeature if you want
                if PlaybackProgressService.shared.getMostRecentlyUpdatedVideoId() != nil {
                    Button {
                        if let latestVideoId = PlaybackProgressService.shared.getMostRecentlyUpdatedVideoId() {
                            if let matchingVideo = videos.first(where: { $0.id == latestVideoId }) {
                                if matchingVideo.status == .postProcessingSuccess {
                                    selectedVideo = matchingVideo
                                } else {
                                    showProcessingAlert = true
                                }
                            }
                        }
                    } label: {
                        HStack(alignment: .center, spacing: 8) {
                            Text("Continue")
                                .font(.headline)

                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 24, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.automatic)
                }
            }

        }
    }
    
    private var loadingRow: some View {
        HStack {
            ProgressView("Loading videos...")
                .progressViewStyle(CircularProgressViewStyle())
                .padding()
        }
        .padding()
        .listRowBackground(Color.black)
    }
    
    @ViewBuilder
    private var emptyOrErrorStateRows: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundColor(.gray.opacity(0.8))
            
            if let error = errorMessage {
                Text("Failed to load videos")
                    .font(.headline)
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
                Text("Go on WatchClips.app and upload some videos to watch here.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 20)
    }
    
    private var offlineBannerRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "wifi.slash")
                .font(.caption2)
            Text("Offline - Showing Cached Videos")
                .font(.caption2)
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
    
    private var logoutButton: some View {
        Section {
            Button(action: {
                showLogoutConfirmation = true
            }) {
                Text("Logout")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
    }
    
    private var deletingOverlay: some View {
        VStack {
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
    
    // MARK: - Methods
    
    /// Fetch the user's latest plan from Supabase (via UserSettingsService).
    private func fetchPlan() async {
        do {
            // 1) Get userId from loggedInState
            if let userId = decodeLoggedInState(from: loggedInStateData)?.userId {
                // 2) Grab the latest plan (or fallback to cache if you prefer).
                let freshPlan = try await mainUserSettingsService.fetchActivePlan(forUserId: userId)
                
                // 3) Update our local @State property
                await MainActor.run {
                    self.plan = freshPlan
                    
                    // --- Update the loggedInStateData here ---
                    if var currentState = decodeLoggedInState(from: loggedInStateData) {
                        // E.g., update planName to reflect the new plan (or fallback to "Free")
                        currentState.planName = freshPlan?.name ?? .free
                        
                        // Re-encode and store it back
                        if let newData = encodeLoggedInState(currentState) {
                            loggedInStateData = newData
                        }
                    }
                }
            }
        } catch {
            // If it fails, plan stays nil
            print("[VideoListView] fetchPlan failed:", error)
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

    /// Also refresh the plan so we always have the most current subscription state.
    private func handleRefresh(forceRefresh: Bool = true) async {
        // 1) Fetch the plan first
        await fetchPlan()
        
        await MainActor.run {
            errorMessage = nil
            isLoading = true
        }
        
        let oldVideos = videos
        defer {
            Task { @MainActor in isLoading = false }
        }
        
        do {
            let fetchedVideos = try await (
                forceRefresh
                ? cachedVideosService.refreshVideos(forCode: code)
                : cachedVideosService.fetchVideos(forCode: code, useCache: true)
            )
            
            let fetchedIDs = Set(fetchedVideos.map { $0.id })
            let missingVideos = oldVideos.filter { !fetchedIDs.contains($0.id) }
            
            await MainActor.run {
                videos = fetchedVideos
                isOffline = false
                errorMessage = nil
                isInitialLoad = false
            }
            
            // Clean up any missing videos from disk
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
        cachedVideosService.loadCachedVideos()
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
                        errorMessage = error.localizedDescription
                        showErrorAlert = true
                    }
                }
            }
        }
    }

    private func deleteAllVideosAndLogout() async {
        await MainActor.run {
            isDeletingAll = true
        }
        defer {
            Task { @MainActor in isDeletingAll = false }
        }
        
        // Clear the entire loggedInState
        await MainActor.run {
            loggedInStateData = Data()  // remove the user's logged-in info
        }
        
        Task.detached {
            await downloadStore.clearAllDownloads()
            await cachedVideosService.clearCache()
            PlaybackProgressService.shared.clearAllProgress()
            VideoDownloadManager.shared.deleteAllSavedVideos()
        }
    }
}
