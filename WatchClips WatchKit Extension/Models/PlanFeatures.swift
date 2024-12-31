//
//  PlanFeatures.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//


import Foundation

/// Represents the features object in your JSON.
struct PlanFeatures: Codable {
    let maxVideos: Int
    let expiresDays: Int
    let audioQuality: String
    let betaFeatures: Bool
    let videoQuality: String
    let fasterUploads: Bool
    let resumeFeature: Bool
    let uploadSizeMb: Int
    let offlinePlayback: Bool
    let prioritySupport: Bool
    let doubleTapGesture: Bool
    let backgroundPlayback: Bool
    
    enum CodingKeys: String, CodingKey {
        case maxVideos       = "max_videos"
        case expiresDays     = "expires_days"
        case audioQuality    = "audio_quality"
        case betaFeatures    = "beta_features"
        case videoQuality    = "video_quality"
        case fasterUploads   = "faster_uploads"
        case resumeFeature   = "resume_feature"
        case uploadSizeMb    = "upload_size_mb"
        case offlinePlayback = "offline_playback"
        case prioritySupport = "priority_support"
        case doubleTapGesture = "double_tap_gesture"
        case backgroundPlayback = "background_playback"
    }
}
