//
//  PlanFeatures.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//


import Foundation

/// Represents the features object in your JSON.
struct PlanFeatures: Equatable, Codable {
    let audioQuality: String
    let betaFeatures: Bool
    let resumeFeature: Bool
    
    enum CodingKeys: String, CodingKey {
        case audioQuality    = "audio_quality"
        case betaFeatures    = "beta_features"
        case resumeFeature   = "resume_feature"
    }
}
