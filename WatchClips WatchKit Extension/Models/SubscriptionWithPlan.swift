//
//  SubscriptionWithPlan.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//


// MARK: - SubscriptionWithPlan
/// Matches the row returned by `select("plan_id, plan:plans(*)")`
struct SubscriptionWithPlan: Decodable {
    let plan_id: Int?
    let plan: Plan?
}