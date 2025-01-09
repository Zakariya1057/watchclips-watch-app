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
    
    /// Fetches the user's active plan from the `subscriptions` table, joined with `plans`.
    /// If no active subscription is found, if multiple are found, or if decoding fails,
    /// it falls back to `plan` with `id = 1`.
    func fetchActivePlan(forUserId userId: UUID?) async throws -> Plan? {
        var subscriptions: [SubscriptionWithPlan] = []
        
        if let userId = userId {
            let userIdString = userId.uuidString
            
            print("User Id: \(userIdString)")
            
            // 1) Perform the query, returning an array (no `.single()`).
            let response = try await client
                .from("subscriptions")
                .select("plan_id, plan:plans(*)")
                .eq("user_id", value: userIdString)
                .eq("status", value: "active")
                .execute()
            
            subscriptions = try JSONDecoder().decode([SubscriptionWithPlan].self, from: response.data)
        }
        
        // 2) Decode the array of subscriptions with associated plan.
        //    If 0 rows are returned, this will decode to an empty array.
        do {
            // 3) Handle the possible array scenarios:
            switch subscriptions.count {
            case 0:
                // No active subscription => fallback to plan with id=1
                print("[UserSettingsService] No active subscription => fetching plan id=1 as fallback.")
                return try await fetchPlanById(1)
                
            case 1:
                // Exactly one subscription
                let sub = subscriptions[0]
                guard let plan = sub.plan else {
                    // Subscription present, but plan is nil => fallback
                    print("[UserSettingsService] Subscription present but plan is nil => fetching plan id=1.")
                    return try await fetchPlanById(1)
                }
                // We have exactly one subscription with a non-nil plan
                return plan
                
            default:
                // More than 1 => treat as an unexpected scenario; fallback to plan id=1
                print("[UserSettingsService] Multiple active subscriptions found => fetching plan id=1 as fallback.")
                return try await fetchPlanById(1)
            }
        } catch {
            // If JSON is malformed or doesn't match our model, treat as no subscription => fallback plan
            print("[UserSettingsService] Error decoding subscription array => \(error) => fetching plan id=1.")
            return try await fetchPlanById(1)
        }
    }
    
    // MARK: - Fetch a single plan by its ID
    private func fetchPlanById(_ id: Int) async throws -> Plan {
        let planResponse = try await client
            .from("plans")
            .select("*")
            .eq("id", value: id)
            .single()
            .execute()
        
        let planData = planResponse.data
        // If this throws, it's good to let it bubble up so the caller knows there's a genuine issue
        let plan = try JSONDecoder().decode(Plan.self, from: planData)
        return plan
    }
}
