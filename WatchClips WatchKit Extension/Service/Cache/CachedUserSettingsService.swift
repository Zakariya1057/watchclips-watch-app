//
//  CachedUserSettingsService.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//

import Foundation
import Combine

class CachedUserSettingsService: ObservableObject {
    private let userSettingsService: UserSettingsService
    private let repository = UserSettingsRepository.shared
    
    init(userSettingsService: UserSettingsService) {
        self.userSettingsService = userSettingsService
    }
    
    // MARK: - Public API
    
    /// Loads the plan from the local DB (SQLite). Returns nil if not found or decoding fails.
    func loadCachedPlan(forUserId userId: UUID) -> Plan? {
        let userIdStr = userId.uuidString
        return repository.loadPlan(for: userIdStr)
    }
    
    /**
     Fetches the user's active plan:
     
     - If `useCache` is `true` and a cached plan is found, returns that **immediately**, then spawns a background task to fetch fresh data from Supabase.
     - If no cache or `useCache` is `false`, fetches from Supabase directly (throws if offline or request fails).
    */
    func fetchActivePlan(forUserId userId: UUID, useCache: Bool = true) async throws -> Plan? {
        let userIdStr = userId.uuidString
        
        // 1) Attempt to load from local cache
        if useCache, let cachedPlan = repository.loadPlan(for: userIdStr) {
            // Return cached plan immediately
            let localResult = cachedPlan
            
            // 2) Meanwhile, try a background refresh
            Task {
                do {
                    // Attempt a remote fetch from Supabase
                    let freshPlan = try await userSettingsService.fetchActivePlan(forUserId: userId)
                    
                    // If we got new data, store in cache. If nil, remove from cache.
                    if let freshPlan {
                        repository.savePlan(freshPlan, for: userIdStr)
                    } else {
                        repository.removePlan(for: userIdStr)
                    }
                } catch {
                    print("[CachedUserSettingsService] Background refresh failed. Keeping cached plan.")
                }
            }
            
            return localResult
            
        } else {
            // 3) If no cache or ignoring cache, fetch from Supabase directly
            let freshPlan = try await userSettingsService.fetchActivePlan(forUserId: userId)
            
            if let freshPlan {
                repository.savePlan(freshPlan, for: userIdStr)
            } else {
                repository.removePlan(for: userIdStr)
            }
            
            return freshPlan
        }
    }
    
    /// Forces a refresh from remote, ignoring cache. Throws if offline or the request fails.
    func refreshActivePlan(forUserId userId: UUID) async throws -> Plan? {
        let userIdStr = userId.uuidString
        let freshPlan = try await userSettingsService.fetchActivePlan(forUserId: userId)
        
        if let freshPlan {
            repository.savePlan(freshPlan, for: userIdStr)
        } else {
            repository.removePlan(for: userIdStr)
        }
        
        return freshPlan
    }
    
    /// Removes the cached plan for a user
    func removeFromCache(forUserId userId: UUID) {
        let userIdStr = userId.uuidString
        repository.removePlan(for: userIdStr)
    }
    
    /// Clears **all** locally cached user plans
    func clearCache() {
        repository.removeAll()
        print("[CachedUserSettingsService] Cleared all user plan cache.")
    }
}
