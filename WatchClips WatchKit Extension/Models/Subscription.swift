//
//  Subscription.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//


import Foundation

struct Subscription: Identifiable, Decodable {
    // Matches 'id uuid'
    let id: UUID
    
    let user_id: UUID
    let plan_id: Int?
    
    let stripe_subscription_id: String?
    let status: String
    
    let current_period_start: Date?
    let current_period_end: Date?
    
    let created_at: Date?
}
