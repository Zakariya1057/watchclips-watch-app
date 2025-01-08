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
    
    @StateObject private var networkMonitor = NetworkMonitor()
    @State private var showProcessingAlert = false
    @State private var pageLoaded = false
    
    @StateObject private var notificationManager = NotificationManager.shared
    var downloadStore: DownloadsStore = DownloadsStore()
    
    // AppState singleton that holds the current selectedVideo
    @StateObject private var appState = AppState.shared
    
    // Decoded "code" from loggedInState
    private var code: String {
        decodeLoggedInState(from: loggedInStateData)?.code ?? ""
    }
    
    // Track last-played
    @State private var lastPlayedVideoId: String?
    
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
                        
                        // MAIN list of videos
                        ForEach(sharedVM.videos) { video in
                            VideoRow(
                                video: video,
                                isDownloaded: downloadStore.isDownloaded(videoId: video.id)
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
                            .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10))
                        }
                    }
                    
                    logoutButton
                }
                .listStyle(.plain)
                
                // Called the FIRST time the view appears (and if navigated away + back)
                .onAppear {
                    DispatchQueue.main.async {
                        // Lazy-load plan info only once
                        if !pageLoaded {
                            Task {
                                await sharedVM.fetchPlan()
                            }
                            pageLoaded = true
                        }
                    }
                }
                
                // If we come back online after being offline, do a refresh
                .onReceive(networkMonitor.$isConnected) { isConnected in
                    if isConnected, sharedVM.isOffline, !sharedVM.isInitialLoad {
                        Task {
                            await sharedVM.refreshVideos(code: code, forceRefresh: true)
                        }
                    }
                }
            }
            // Navigation Bar items
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let planName = sharedVM.activePlan?.name {
                        PlanBadgeView(planName: planName)
                    }
                }
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
            // Logout confirmation
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
            // Processing alert
            .alert("Processing...", isPresented: $showProcessingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Optimizing video for Apple Watch. Please wait...")
            }
        }
        // Whenever "appState.selectedVideo" changes from a Video to nil, it means the fullscreen was dismissed
        .onChange(of: appState.selectedVideo) { newValue in
            if newValue == nil {
                // The user just dismissed the video player => refresh last played
                setLastPlayedVideo()
            }
        }
        
        // When the user dismisses the "DownloadList" screen (true -> false)
        .onChange(of: showDownloadList) { newValue in
            if !newValue {
                // The user closed the downloads screen => refresh last played
                setLastPlayedVideo()
            }
        }
        
        // Also call setLastPlayedVideo each time this view fully appears
        .onAppear {
            DispatchQueue.main.async {
                setLastPlayedVideo()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    func setLastPlayedVideo() {
        print("Set Last Played Video called")
        lastPlayedVideoId = PlaybackProgressService.shared.getMostRecentlyUpdatedVideoId()
    }
    
    private func deleteAllVideosAndLogout() async {
        await sharedVM.deleteAllVideosAndLogout(downloadStore: downloadStore)
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
        // Fullscreen cover for downloads
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
            // If the plan includes a "resume" feature, show "Continue" button
            if let resume = sharedVM.activePlan?.features?.resumeFeature, resume == true {
                if lastPlayedVideoId != nil {
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
    
    private var loadingRow: some View {
        HStack {
            ProgressView("Loading videos...")
                .progressViewStyle(CircularProgressViewStyle())
                .padding()
        }
        .padding()
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
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }
    
    private var logoutButton: some View {
        Section {
            Button {
                showLogoutConfirmation = true
            } label: {
                Text("Logout")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
    }
}
