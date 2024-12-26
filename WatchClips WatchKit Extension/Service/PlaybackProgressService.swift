//
//  PlaybackProgressService.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 25/12/2024.
//

import Foundation

final class PlaybackProgressService {
    static let shared = PlaybackProgressService()
    
    private let userDefaults = UserDefaults.standard
    
    private func key(forVideoId videoId: String) -> String {
        return "PlaybackProgress-\(videoId)"
    }
    
    func getProgress(for videoId: String) -> Double? {
        let progress = userDefaults.double(forKey: key(forVideoId: videoId))
        return userDefaults.object(forKey: key(forVideoId: videoId)) == nil ? nil : progress
    }
    
    func setProgress(_ progress: Double, for videoId: String) {
        userDefaults.set(progress, forKey: key(forVideoId: videoId))
    }
    
    func clearProgress(for videoId: String) {
        userDefaults.removeObject(forKey: key(forVideoId: videoId))
    }
    
   func clearAllProgress() {
        let defaults = UserDefaults.standard
        
        // Loop through all keys in UserDefaults
        for key in defaults.dictionaryRepresentation().keys {
            // If it has our prefix, remove it
            if key.hasPrefix("PlaybackProgress-") {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
