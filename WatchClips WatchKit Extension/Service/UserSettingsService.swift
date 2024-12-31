//
//  UserSettingsService.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//

import Foundation
import Combine
import Supabase

// MARK: - UserSettingsService
/// A service to fetch the user's active plan from Supabase.
class UserSettingsService: ObservableObject {
    private let client: SupabaseClient
    
    init(client: SupabaseClient) {
        self.client = client
    }
    
    /// Fetches the user's active plan from the `subscriptions` table, joined with `plans`,
    /// and returns `nil` if no active subscription is found.
    func fetchActivePlan(forUserId userId: UUID) async throws -> Plan? {
        let userIdString = userId.uuidString
        
        // 1) Perform the query
        let response = try await client
            .from("subscriptions")
            .select("plan_id, plan:plans(*)")
            .eq("user_id", value: userIdString)
            .eq("status", value: "active")
            .single() // Throws if 0 or >1 rows
            .execute()
        
        // 2) `response.data` is non-optional Data in newer supabase-swift.
        //    If the request fails, it throws earlier. If no rows match, `.single()` might also throw.
        //    So if we got here, we likely have some JSON data. But it could be empty if the row is empty or not found.
        let rawData = response.data
        
        // If it's empty, treat as no subscription => nil (Free plan).
        if rawData.isEmpty {
            return nil
        }
        
        // 3) Attempt to decode the single row as SubscriptionWithPlan
        do {
            let subWithPlan = try JSONDecoder().decode(SubscriptionWithPlan.self, from: rawData)
            // Return the embedded Plan object (if any)
            return subWithPlan.plan
        } catch {
            print(error)
            // If JSON is malformed or doesn't match our model, treat as no subscription
            return nil
        }
    }
}
