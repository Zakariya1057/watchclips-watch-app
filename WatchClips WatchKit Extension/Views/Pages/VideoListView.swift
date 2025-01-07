//
//  VideoListView.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//

import SwiftUI

struct VideoListView: View {
    @AppStorage("loggedInState") private var loggedInStateData = Data()
    
    // Access your userSettingsService from the environment
    @EnvironmentObject private var mainUserSettingsService: UserSettingsService
    
    // Access the shared videos VM from environment
    @EnvironmentObject private var sharedVM: SharedVideosViewModel
    
    @State private var showErrorAlert = false
    @State private var showLogoutConfirmation = false
    @State private var showDownloadList = false
    
    @State private var isDeletingAll = false
    @StateObject private var networkMonitor = NetworkMonitor()
    @State private var showProcessingAlert = false
    @State private var selectedVideo: Video? // For fullScreenCover
    @State private var pageLoaded = false
    
    @StateObject private var notificationManager = NotificationManager.shared
    var downloadStore: DownloadsStore = DownloadsStore()
    
    private var activePlan: Plan? {
        // Optionally read from sharedVM.activePlan if you want
        // or decode from loggedInState
        if let plan = sharedVM.activePlan {
            return plan
        }
        return decodeLoggedInState(from: loggedInStateData)?.activePlan
    }
    
    private var code: String {
        decodeLoggedInState(from: loggedInStateData)?.code ?? ""
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    downloadsLink
                    continueWatching
                    
                    if sharedVM.isLoading {
                        loadingRow
                    }
                    
                    if sharedVM.videos.isEmpty && !sharedVM.isLoading {
                        emptyOrErrorStateRows
                    } else {
                        if sharedVM.isOffline {
                            offlineBannerRow
                        }
                        
                        ForEach(sharedVM.videos) { video in
                            VideoRow(
                                video: video,
                                isDownloaded: downloadStore.isDownloaded(videoId: video.id)
                            )
                            // Removed .contentShape(Rectangle()) to avoid gesture conflicts
                            .onTapGesture {
                                if video.status == .postProcessingSuccess {
                                    selectedVideo = video
                                } else {
                                    showProcessingAlert = true
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10))
                        }
                    }
                    
                    logoutButton
                }
                // Keep using .plain for minimal styling
                .listStyle(.plain)
                .onAppear {
                    DispatchQueue.main.async {
                        if !pageLoaded {
                            Task {
                                await fetchPlan()
                            }
                            pageLoaded = true
                        }
                    }
                }
                .onReceive(networkMonitor.$isConnected) { isConnected in
                    // If reconnected, refresh if previously offline
                    if isConnected, sharedVM.isOffline, !sharedVM.isInitialLoad {
                        Task {
                            await sharedVM.refreshVideos(code: code, forceRefresh: true)
                        }
                    }
                }
                
                if isDeletingAll {
                    deletingOverlay
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PlanBadgeView(planName: activePlan?.name ?? .free)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        Task {
                            await sharedVM.refreshVideos(code: code, forceRefresh: true)
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sharedVM.errorMessage ?? "An unknown error occurred.")
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
                VideoPlayerView(code: video.code, videoId: video.id, filename: video.filename)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var downloadsLink: some View {
        Button(action: {
            showDownloadList = true
        }) {
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
        // Present the DownloadList modally
        .fullScreenCover(isPresented: $showDownloadList) {
            NavigationStack {
                DownloadList(code: code)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showDownloadList = false
                            }
                        }
                    }
            }
        }
    }

    private var continueWatching: some View {
        Group {
            if let resume = activePlan?.features?.resumeFeature, resume == true {
                if PlaybackProgressService.shared.getMostRecentlyUpdatedVideoId() != nil {
                    Button {
                        if let latestVideoId = PlaybackProgressService.shared.getMostRecentlyUpdatedVideoId() {
                            if let matchingVideo = sharedVM.videos.first(where: { $0.id == latestVideoId }) {
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
        // Removed .listRowBackground(Color.black)
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
        // Removed .listRowBackground(Color.clear)
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
    
    private func fetchPlan() async {
        do {
            if let userId = decodeLoggedInState(from: loggedInStateData)?.userId {
                let freshPlan = try await mainUserSettingsService.fetchActivePlan(forUserId: userId)
                
                // Optionally store it in the shared VM as well
                sharedVM.activePlan = freshPlan
                
                // Or update your loggedInState again
                if var currentState = decodeLoggedInState(from: loggedInStateData) {
                    currentState.activePlan = freshPlan
                    if let newData = encodeLoggedInState(currentState) {
                        loggedInStateData = newData
                    }
                }
            }
        } catch {
            print("[VideoListView] fetchPlan failed:", error)
        }
    }
    
    private func deleteAllVideosAndLogout() async {
        isDeletingAll = true
        defer { isDeletingAll = false }
        
        await sharedVM.deleteAllVideosAndLogout(downloadStore: downloadStore)
    }
}
