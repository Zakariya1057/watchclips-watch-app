import SwiftUI

struct VideoListView: View {
    @AppStorage("loggedInState") private var loggedInStateData = Data()
    
    @EnvironmentObject private var mainUserSettingsService: UserSettingsService
    @EnvironmentObject private var sharedVM: SharedVideosViewModel
    @EnvironmentObject private var playbackProgressService: PlaybackProgressService
    
    @State private var showErrorAlert = false
    @State private var showDownloadList = false
    
    @StateObject private var networkMonitor = NetworkMonitor()
    @State private var showProcessingAlert = false
    @State private var pageLoaded = false
    
    @StateObject private var notificationManager = NotificationManager.shared
    
    // AppState singleton that holds the current selectedVideo
    @StateObject private var appState = AppState.shared
    
    // Decoded "code" from loggedInState
    private var code: String {
        decodeLoggedInState(from: loggedInStateData)?.code ?? ""
    }
    
    // MARK: Loading-state properties
    @State private var showLoadingIndicator = false      // True if we are in a loading state
    @State private var isLongWait = false                // True if we've been loading for more than 2 seconds
    @State private var loadingDelayTask: Task<Void, Never>? = nil
    
    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    downloadsLink
                    continueWatching
                    
                    if showLoadingIndicator {
                        LoadingOverlayView(isLongWait: isLongWait, hideSpinner: true)
                    }
                    
                    if sharedVM.isOffline {
                        OfflineBannerView()
                    }
                    
                    if sharedVM.videos.isEmpty {
                        emptyOrErrorStateRows
                    } else {
                        ForEach(Array(sharedVM.videos.enumerated()), id: \.element.id) { index, video in
                            let currentProgressInSeconds = sharedVM.activePlan?.features?.resumeFeature == true
                            ? playbackProgressService.getProgress(videoId: video.id)?.progress ?? 0
                            : nil
                            
                            VideoRow(
                                video: video,
                                isDownloaded: DownloadsStore.shared.isDownloaded(videoId: video.id),
                                watchProgress: currentProgressInSeconds
                            )
                            .onTapGesture {
                                if video.status == .postProcessingSuccess {
                                    // Present the selected video
                                    appState.selectedVideo = video
                                } else {
                                    // Show alert that video is still processing
                                    showProcessingAlert = true
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                        }
                    }
                }
                .listStyle(.plain)
                
                // Called the FIRST time the view appears
                .onAppear {
                    DispatchQueue.main.async {
                        // Lazy-load plan info only once
                        if !pageLoaded {
                            Task {
                                await sharedVM.fetchPlan(useCache: false)
                            }
                            pageLoaded = true
                        }
                    }
                }
                // If we come back online after being offline, do a refresh
                .onReceive(networkMonitor.$isConnected) { isConnected in
                    if isConnected, sharedVM.isOffline, !sharedVM.isInitialLoad {
                        Task {
                            sharedVM.isOffline = true
                            await sharedVM.refreshVideos(code: code, forceRefresh: true)
                        }
                    }
                }
            }
            // Watch for changes in isLoading to drive our custom loading states
            .onChange(of: sharedVM.isLoading) { newValue in
                if newValue {
                    // We just started loading => immediately show "Loading videos..."
                    showLoadingIndicator = true
                    isLongWait = false
                    
                    // Cancel any existing delay
                    loadingDelayTask?.cancel()
                    
                    // Start a new 2-second delay => afterwards, if still loading, show the "long wait" message
                    loadingDelayTask = Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                        if !Task.isCancelled && sharedVM.isLoading {
                            isLongWait = true
                        }
                    }
                } else {
                    // Loading finished => hide everything
                    showLoadingIndicator = false
                    isLongWait = false
                    loadingDelayTask?.cancel()
                }
            }
            .toolbar {
//                ToolbarItem(placement: .topBarLeading) {
//                    if let planName = sharedVM.activePlan?.name {
//                        PlanBadgeView(planName: planName)
//                    }
//                }
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
            // Error alert
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sharedVM.errorMessage ?? "An unknown error occurred.")
            }
            // Processing alert
            .alert("Processing...", isPresented: $showProcessingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Optimizing video for Apple Watch. Please wait...")
            }
        }
    }
    
    // MARK: - Subviews
    
    private var downloadsLink: some View {
        Button {
            showDownloadList = true
        } label: {
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
            DispatchQueue.main.async {
                notificationManager.requestAuthorization()
            }
        }
        .fullScreenCover(isPresented: $showDownloadList) {
            ZStack {
                Color.black
                    .opacity(0.5)
                    .ignoresSafeArea()
                
                DownloadList(code: code)
            }
        }
    }

    private var continueWatching: some View {
        Group {
            if !sharedVM.videos.isEmpty, let resume = sharedVM.activePlan?.features?.resumeFeature, resume == true {
                if let lastPlayedVideoId = playbackProgressService.lastPlayedVideoId {
                    Button {
                        if let matchingVideo = sharedVM.videos.first(where: { $0.id == lastPlayedVideoId }) {
                            if matchingVideo.status == .postProcessingSuccess {
                                appState.selectedVideo = matchingVideo
                            } else {
                                showProcessingAlert = true
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
    
    @ViewBuilder
    private var emptyOrErrorStateRows: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundColor(.gray.opacity(0.8))
            
            if let error = sharedVM.errorMessage {
                Text("Failed to load videos")
                    .font(.headline)
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Retry") {
                    Task {
                        await sharedVM.refreshVideos(code: code, forceRefresh: true)
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
}
