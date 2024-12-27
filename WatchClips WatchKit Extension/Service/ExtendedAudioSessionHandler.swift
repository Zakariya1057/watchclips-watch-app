////
////  ExtendedAudioSessionHandler.swift
////  WatchClips
////
////  Created by Zakariya Hassan on 27/12/2024.
////
//
//
//import WatchKit
//import AVFoundation
//
///// A helper to request extended audio runtime on watchOS.
//class ExtendedAudioSessionHandler: NSObject, ObservableObject, WKExtendedRuntimeSessionDelegate {
//    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: (any Error)?) {
//        <#code#>
//    }
//    
//    private var session: WKExtendedRuntimeSession?
//
//    /// Call this to start the extended runtime session, letting your audio continue when app goes background.
//    func startSession() {
//        // Create a config specifying you want extended time for audio.
//        let config = WKExtendedRuntimeSessionConfiguration()
//        config.applicationType = .audio
//
//        let session = WKExtendedRuntimeSession(configuration: config)
//        session.delegate = self
//        session.start() // Request extended runtime
//        self.session = session
//    }
//
//    // MARK: - WKExtendedRuntimeSessionDelegate
//
//    func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {
//        // Great! The watch granted extended time; your AVPlayer can keep playing in background.
//        print("Extended runtime session DID START (audio).")
//    }
//
//    func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {
//        // The system will end the session soon (e.g., low battery).
//        print("Extended runtime session WILL EXPIRE.")
//        // You might pause and save playback state, etc.
//    }
//
//    func extendedRuntimeSessionDidInvalidate(_ session: WKExtendedRuntimeSession) {
//        // The session ended (user or system forcibly).
//        print("Extended runtime session DID INVALIDATE.")
//        // Audio may be stopped now; handle cleanup or UI updates.
//    }
//}
