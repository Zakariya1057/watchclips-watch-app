//
//  VideoPlayerView.swift
//  YourAppName
//
//  Created by Your Name on SomeDate.
//

import SwiftUI
import AVKit
import AVFoundation
import MediaPlayer
import UIKit

struct VideoPlayerView: View {
    @State var remoteURL: URL
    private let code: String
    private let videoId: String
    private let fileExtension: String
    @State private var image: URL
    
    @EnvironmentObject private var playbackProgressService: PlaybackProgressService
    @EnvironmentObject private var sharedVM: SharedVideosViewModel
    
    // ***** 1) Inject SettingsStore to read resumeWhereLeftOff
    @EnvironmentObject private var settingsStore: SettingsStore
    
    @State private var video: Video?
    
    @State private var isPlaying: Bool = true
    @State private var seekTime: Double = 0
    @State private var isLoading = true
    @State private var player: AVPlayer?
    @State private var playerItemStatusObservation: NSKeyValueObservation?
    @State private var timeControlStatusObservation: NSKeyValueObservation?
    @State private var downloadError: String?
    @State private var statusObservation: NSKeyValueObservation?
    @State private var lastPlaybackTime: Double = 0.0
    @State private var wasPlayingBeforeSwitch = false
    @State private var currentlyUsingLocal = true
    @State private var didStartSetup = false
    
    private let videosService = CachedVideosService(videosService: VideosService(client: supabase))
    
    @AppStorage("loggedInState") private var loggedInStateData = Data()
    
    private var activePlan: Plan? {
        return decodeLoggedInState(from: loggedInStateData)?.activePlan
    }
    
    // For saving and resuming
    @State private var timeObserverToken: Any?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - Init
    init(video: Video) {
        self.code = video.code
        self.videoId = video.id
        
        // Default remote URL
        guard let url = URL(string: "https://dwxvsu8u3eeuu.cloudfront.net/\(video.filename)") else {
            fatalError("Invalid URL constructed with code: \(code) and videoId: \(videoId)")
        }
        self.remoteURL = url
        self.fileExtension = url.pathExtension
        
        guard let imageUrl = URL(string: "https://dwxvsu8u3eeuu.cloudfront.net/\(video.image ?? "")") else {
            fatalError("Invalid URL constructed with code: \(code) and videoId: \(videoId)")
        }
        self.image = imageUrl
        
        self.video = video
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // Invisible tap target to toggle play/pause with a tap
            Button {
                isPlaying ? player?.pause() : player?.play()
            } label: { }
            .background(.purple)
            .frame(width: 60, height: 60)
            .handGestureShortcut(.primaryAction)
            .opacity(0)
            .zIndex(0)
            .onAppear {
                print("Image: \(self.image)")
            }
            
            // Loading overlay (shows image & progress if still loading and no error)
            if isLoading && downloadError == nil {
                ZStack {
                    GeometryReader { proxy in
                        let size = proxy.size
                        
                        if fileExtension == "mp4" {
                            CachedAsyncImage(
                                url: self.image,
                                height: size.height
                            ) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: size.width, height: size.height)
                            }
                        } else {
                            Image("audio")
                                .resizable()
                                .scaledToFit()
                                .frame(width: size.width, height: size.height)
                        }
                    }
                    
                    Color.black
                        .opacity(0.8)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        if !currentlyUsingLocal {
                            Text("Tip:\nDownload for faster playback.")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity)
                        }
                        ProgressView()
                            .scaleEffect(2.0)
                            .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
                    }
                }
                .zIndex(3)
            }
            
            // The AVPlayer-based VideoPlayer
            if let player = player {
                VideoPlayer(player: player)
                    .opacity(downloadError == nil ? 1 : 0)
                    .onAppear {
                        // Possibly resume; logic is handled in initializePlayer()
                    }
                    .onDisappear {
                        // 1) Save state
                        wasPlayingBeforeSwitch = isPlaying
                        player.pause()
                        
                        // 2) Remove time observer
                        if let observerToken = timeObserverToken {
                            player.removeTimeObserver(observerToken)
                            timeObserverToken = nil
                        }
                        
                        // 3) Replace current item => ensures audio truly stops
                        player.replaceCurrentItem(with: nil)
                        
                        // 4) Release player
                        self.player = nil
                        
                        // 5) Dismiss the view
                        dismiss()
                    }
                    .zIndex(2)
            }
            
            // Error overlay
            if let error = downloadError {
                ZStack(alignment: .center) {
                    Color.black
                        .opacity(1)
                        .ignoresSafeArea()
                    
                    VStack(alignment: .center, spacing: 10) {
                        Text("Error loading video")
                            .foregroundColor(.white)
                            .font(.headline)
                        
                        Text(error)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Retry") {
                            downloadError = nil
                            prepareToPlay()
                        }
                        .foregroundColor(.white)
                        .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .zIndex(3)
            }
        }
        .toolbar {
            // Hidden trailing item to keep layout consistent
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {}) { }
                    .opacity(0)
            }
        }
        .scrollIndicators(.hidden)
        .toolbar(downloadError != nil ? .visible : (isLoading ? .visible : .hidden))
        .onAppear {
            Task {
                video = try? await videosService.fetchVideo(forCode: code, forVideoId: videoId)
            }
            
            if !didStartSetup {
                didStartSetup = true
                DispatchQueue.main.async {
                    prepareToPlay()
                }
            }
        }
        .onDisappear {
            statusObservation = nil
            
            // Clean up the AVPlayer
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
        }
    }
    
    // MARK: - Loading Logic
    private func prepareToPlay() {
        guard downloadError == nil else { return }
        
        // 1) Check local file first
        if SegmentedDownloadManager.shared.doesLocalFileExist(videoId: videoId, fileExtension: fileExtension) {
            let localURL = SegmentedDownloadManager.shared.localFileURL(videoId: videoId, fileExtension: fileExtension)
            print("Playing from local: \(localURL)")
            currentlyUsingLocal = true
            setupPlayerForLocalFile(localURL, fallbackToRemote: true)
        } else {
            print("Playing from remote: \(remoteURL)")
            currentlyUsingLocal = false
            setupPlayerForRemote(remoteURL)
        }
        
        setupRemoteCommandCenter()
    }
    
    private func setupPlayerForLocalFile(_ localURL: URL, fallbackToRemote: Bool) {
        let asset = AVURLAsset(url: localURL)
        asset.loadValuesAsynchronously(forKeys: ["playable"]) {
            DispatchQueue.main.async {
                var error: NSError?
                let status = asset.statusOfValue(forKey: "playable", error: &error)
                if status == .loaded, asset.isPlayable {
                    let newItem = AVPlayerItem(asset: asset)
                    initializePlayer(with: newItem, restoreState: true)
                } else {
                    print("Local file not playable - falling back to URL")
                    self.currentlyUsingLocal = false
                    if fallbackToRemote {
                        self.setupPlayerForRemote(self.remoteURL)
                    } else {
                        self.downloadError = "Local file is not playable."
                    }
                }
            }
        }
    }
    
    private func setupPlayerForRemote(_ url: URL) {
        print("Playing from remote URL => \(url)")
        let playerItem = AVPlayerItem(url: url)
        initializePlayer(with: playerItem, restoreState: false)
    }
    
    private func initializePlayer(with playerItem: AVPlayerItem, restoreState: Bool) {
        // Save last playback time from the old player if needed
        if let existingPlayer = player {
            lastPlaybackTime = existingPlayer.currentTime().seconds
            wasPlayingBeforeSwitch = isPlaying
        }
        
        // Release any existing player
        player = nil
        
        let newPlayer = AVPlayer(playerItem: playerItem)
        player = newPlayer
        
        // Observe AVPlayerItem status
        playerItemStatusObservation = playerItem.observe(\.status, options: [.new]) { item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    updateNowPlayingInfo()
                    
                    // ***** 2) Resume only if user is Pro AND "resumeWhereLeftOff" is true
                    if sharedVM.activePlan?.name == .pro,
                       settingsStore.settings.resumeWhereLeftOff,
                       let (progress, _) = playbackProgressService.getProgress(videoId: videoId),
                       progress > 0
                    {
                        seekTo(time: progress, playIfNeeded: isPlaying)
                    }
                    
                    // Add periodic time observer for progress updates
                    timeObserverToken = newPlayer.addPeriodicTimeObserver(
                        forInterval: CMTimeMake(value: 1, timescale: 1),
                        queue: .main
                    ) { _ in
                        let currentTime = newPlayer.currentTime().seconds
                        playbackProgressService.setProgress(videoId: videoId, progress: currentTime)
                        updateNowPlayingInfo()
                    }
                    
                    // Ensure correct playback state
                    updatePlaybackStateIfReady()
                    isLoading = false
                    
                case .failed:
                    handlePlaybackError(
                        item.error,
                        attemptedURL: currentlyUsingLocal
                            ? SegmentedDownloadManager.shared.localFileURL(videoId: videoId, fileExtension: fileExtension)
                            : remoteURL,
                        fallbackToRemote: !currentlyUsingLocal
                    )
                    
                default:
                    break
                }
            }
        }
        
        // Observe player's timeControlStatus (playing/paused)
        timeControlStatusObservation = newPlayer.observe(\.timeControlStatus, options: [.new]) { p, _ in
            DispatchQueue.main.async {
                switch p.timeControlStatus {
                case .playing:
                    isPlaying = true
                case .paused:
                    isPlaying = false
                default:
                    break
                }
            }
        }
        
        // If restoring state, seek to lastPlaybackTime
        if restoreState {
            seekTo(time: lastPlaybackTime, playIfNeeded: false)
            if wasPlayingBeforeSwitch {
                isPlaying = true
                updatePlaybackStateIfReady()
            }
        }
        
        // Configure audio
        configureAudioSession()
    }
    
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }
    }
    
    private func handlePlaybackError(_ error: Error?, attemptedURL: URL, fallbackToRemote: Bool) {
        print("Playback error:", error as Any, " Attempted URL:", attemptedURL)
        
        if fallbackToRemote && attemptedURL != remoteURL {
            currentlyUsingLocal = false
            setupPlayerForRemote(remoteURL)
        } else {
            downloadError = error?.localizedDescription ?? "Unknown playback error."
        }
    }
    
    // MARK: - Remote Command Center
    private func setupRemoteCommandCenter() {
        let cmd = MPRemoteCommandCenter.shared()
        
        cmd.playCommand.isEnabled = true
        cmd.playCommand.addTarget { [self] _ in
            player?.play()
            isPlaying = true
            updateNowPlayingInfo()
            return .success
        }
        
        cmd.pauseCommand.isEnabled = true
        cmd.pauseCommand.addTarget { [self] _ in
            player?.pause()
            isPlaying = false
            updateNowPlayingInfo()
            return .success
        }
        
        cmd.togglePlayPauseCommand.isEnabled = true
        cmd.togglePlayPauseCommand.addTarget { [self] _ in
            if isPlaying {
                player?.pause()
                isPlaying = false
            } else {
                player?.play()
                isPlaying = true
            }
            updateNowPlayingInfo()
            return .success
        }
    }
    
    // MARK: - Now Playing Info
    private func updateNowPlayingInfo() {
        guard let player = player,
              let currentItem = player.currentItem else {
            return
        }
        
        let currentTime = player.currentTime().seconds
        let duration = currentItem.duration.seconds
        
        var nowPlayingInfo: [String: Any] = [:]
        nowPlayingInfo[MPMediaItemPropertyTitle] = video?.title ?? "Untitled"
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    // MARK: - Playback State
    private func updatePlaybackStateIfReady() {
        guard let p = player,
              let item = p.currentItem,
              item.status == .readyToPlay else {
            return
        }
        
        if isPlaying {
            p.playImmediately(atRate: 1.0)
        } else {
            p.pause()
        }
    }
    
    private func seekTo(time: Double, playIfNeeded: Bool) {
        guard let p = player else { return }
        let targetTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        p.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            if playIfNeeded {
                p.play()
            }
        }
    }
}
