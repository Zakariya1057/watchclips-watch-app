import SwiftUI
import AVKit
import AVFoundation

struct VideoPlayerView: View {
    @State var remoteURL: URL
    
    private let code: String
    private let videoId: String
    
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
    @State private var currentlyUsingLocal = false
    @State private var didStartSetup = false
    
    @State private var scale: CGFloat = 1.0
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    
    init(code: String, videoId: String) {
        self.code = code
        self.videoId = videoId
        
        // Default remote URL
        guard let url = URL(string: "https://dwxvsu8u3eeuu.cloudfront.net/processed/\(code)/\(videoId).mp4") else {
            fatalError("Invalid URL constructed with code: \(code) and videoId: \(videoId)")
        }
        self.remoteURL = url
    }
    
    var body: some View {
        ZStack {
            // Invisible tap target (Apple Watch uses .handGestureShortcut)
            Button {
                isPlaying ? player?.pause() : player?.play()
            } label: { }
            .background(.purple)
            .frame(width: 60, height: 60)
            .handGestureShortcut(.primaryAction)  // Apple Watch specific
            .opacity(0)
            .zIndex(0)
            
            // Loading overlay
            if isLoading && downloadError == nil {
                Color.black.opacity(0.8)
                    .ignoresSafeArea()
                    .zIndex(3)
                ProgressView()
                    .foregroundColor(.white)
                    .scaleEffect(2.0)
                    .zIndex(3)
            }
            
            // The AVPlayer-based VideoPlayer
            if let player = player {
                VideoPlayer(player: player)
                    .scaleEffect(scale)
                    .onTapGesture(count: 2) {
                        withAnimation {
                            scale = (scale == 1.0) ? 2.0 : 1.0
                        }
                    }
                    .onAppear {
                        if isPlaying {
                            player.play()
                        }
                    }
                    .onDisappear {
                        // Save state, then dismiss
                        wasPlayingBeforeSwitch = isPlaying
                        player.pause()
                        dismiss()
                    }
                    .zIndex(2)
            }

            // Error overlay
            if let error = downloadError {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                VStack {
                    Text("Error loading video")
                        .foregroundColor(.white)
                        .padding()
                    Text(error)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Retry") {
                        downloadError = nil
                        prepareToPlay()
                    }
                    .padding()
                    .foregroundColor(.white)
                }
                .zIndex(3)
            }
        }
        .toolbar {
            // Hidden trailing item for layout
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {}) {}.opacity(0)
            }
        }
        .scrollIndicators(.hidden)
        .toolbar(downloadError != nil ? .visible : (isLoading ? .visible : .hidden))
        .onAppear {
            if !didStartSetup {
                didStartSetup = true
                DispatchQueue.main.async {
                    prepareToPlay()
                }
            }
        }
        .onDisappear {
            // Cleanup
            statusObservation = nil
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                // App is active again, resume if was playing
                if wasPlayingBeforeSwitch {
                    wasPlayingBeforeSwitch = false
                    if let player = player {
                        isPlaying = true
                        player.play()
                    }
                }
            case .inactive, .background:
                // Save state, pause
                wasPlayingBeforeSwitch = isPlaying
                player?.pause()
            @unknown default:
                break
            }
        }
    }
    
    // MARK: - Loading Logic
    
    private func prepareToPlay() {
        guard downloadError == nil else { return }

        // 1) Check if there's a local .mp4 file for this (code, videoId).
        //    This method is from the revised ForegroundDownloadManager that
        //    uses the consistent naming (e.g., "code-videoId.mp4").
        if ForegroundDownloadManager.shared.doesLocalFileExist(videoId: videoId) {
            print("Playing from local")
            // Actually get the local file URL
            let localURL = ForegroundDownloadManager.shared.localFileURL(videoId: videoId)
            currentlyUsingLocal = true
            setupPlayerForLocalFile(localURL, fallbackToRemote: true)
        } else {
            print("Playing from remote")
            // 2) Otherwise, fallback to remote
            currentlyUsingLocal = false
            setupPlayerForRemote(remoteURL)
        }
    }

    private func setupPlayerForLocalFile(_ localURL: URL, fallbackToRemote: Bool) {
        let asset = AVURLAsset(url: localURL)
        asset.loadValuesAsynchronously(forKeys: ["playable"]) {
            DispatchQueue.main.async {
                var error: NSError?
                let status = asset.statusOfValue(forKey: "playable", error: &error)
                if status == .loaded, asset.isPlayable {
                    let newItem = AVPlayerItem(asset: asset)
                    self.initializePlayer(with: newItem, restoreState: true)
                } else {
                    // If local is not playable, fallback to remote if allowed
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
        let playerItem = AVPlayerItem(url: url)
        playerItem.preferredForwardBufferDuration = 0
        initializePlayer(with: playerItem, restoreState: false)
    }

    private func initializePlayer(with playerItem: AVPlayerItem, restoreState: Bool) {
        // If there's an existing player, save the last playback time
        if let existingPlayer = player {
            lastPlaybackTime = existingPlayer.currentTime().seconds
            wasPlayingBeforeSwitch = isPlaying
        }

        // Release any old player
        self.player = nil

        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        self.player = newPlayer

        // Observe the AVPlayerItem's status for readiness
        self.playerItemStatusObservation = playerItem.observe(\.status, options: [.new]) { item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.updatePlaybackStateIfReady()
                case .failed:
                    // If local fails, fallback to remote if not already remote
                    self.handlePlaybackError(
                        item.error,
                        attemptedURL: self.currentlyUsingLocal
                            ? ForegroundDownloadManager.shared.localFileURL(videoId: self.videoId)
                            : self.remoteURL,
                        fallbackToRemote: !self.currentlyUsingLocal
                    )
                default:
                    break
                }
            }
        }

        // Observe player's timeControlStatus to update isPlaying
        self.timeControlStatusObservation = newPlayer.observe(\.timeControlStatus, options: [.new]) { player, _ in
            DispatchQueue.main.async {
                switch player.timeControlStatus {
                case .playing:
                    isPlaying = true
                case .paused:
                    isPlaying = false
                default:
                    break
                }
            }
        }

        // Restore previous seekTime, if any
        if self.seekTime > 0 {
            self.seekTo(time: self.seekTime, playIfNeeded: false)
        }

        // If we had a partial session, restore that playback time + status
        if restoreState {
            self.seekTo(time: self.lastPlaybackTime, playIfNeeded: false)
            if self.wasPlayingBeforeSwitch {
                self.isPlaying = true
                self.updatePlaybackStateIfReady()
            }
        } else {
            self.updatePlaybackStateIfReady()
        }
    }

    private func handlePlaybackError(_ error: Error?, attemptedURL: URL, fallbackToRemote: Bool) {
        if fallbackToRemote && attemptedURL != self.remoteURL {
            // Switch from local to remote
            self.currentlyUsingLocal = false
            self.setupPlayerForRemote(self.remoteURL)
        } else {
            // Just show the error
            self.downloadError = error?.localizedDescription ?? "Unknown playback error."
        }
    }

    private func tearDownObservations() {
        playerItemStatusObservation = nil
        timeControlStatusObservation = nil
    }

    private func updatePlaybackStateIfReady() {
        guard let player = player,
              let playerItem = player.currentItem,
              playerItem.status == .readyToPlay else {
            return
        }

        if isPlaying {
            player.playImmediately(atRate: 1.0)
        } else {
            player.pause()
        }
    }

    private func seekTo(time: Double, playIfNeeded: Bool = true) {
        guard let player = player else { return }
        let targetTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))

        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            if self.isPlaying && playIfNeeded {
                player.playImmediately(atRate: 1.0)
            }
        }
    }
}
