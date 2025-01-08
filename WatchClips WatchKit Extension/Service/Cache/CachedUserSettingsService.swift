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
    
    // MARK: - Local Cache Only
    
    /// Loads the single plan from the local DB (SQLite). Returns `nil` if not found or decoding fails.
    func loadCachedPlan() -> Plan? {
        return repository.loadPlan()
    }
    
    // MARK: - Fetch with Optional userId
    
    /**
     Fetches the user's active plan:
     
     - If `useCache` is `true` and a cached plan is found, returns that **immediately**,
       then spawns a background task to fetch fresh data from the remote service (if `userId` is non-nil).
     - If no cache or `useCache` is `false`, fetches from the remote service directly (throws if offline or request fails).
     - If `userId` is `nil`, only local cache will be used (if `useCache == true`).
    */
    func fetchActivePlan(forUserId userId: UUID?, useCache: Bool = true) async throws -> Plan? {
        
        // If userId is nil, we cannot fetch from remote. Use cache if possible, else return nil.
        guard let userId = userId else {
            if useCache {
                // Return whatever is in local cache
                return loadCachedPlan()
            } else {
                // No remote fetch possible, skip local, return nil
                return nil
            }
        }
        
        // 1) Attempt to load from local cache
        if useCache, let cachedPlan = repository.loadPlan() {
            // Return cached plan immediately
            let localResult = cachedPlan
            
            // 2) Meanwhile, try a background refresh
            Task {
                do {
                    // Attempt a remote fetch (userId is guaranteed here)
                    let freshPlan = try await userSettingsService.fetchActivePlan(forUserId: userId)
                    
                    // If we got new data, store in cache. If nil, remove from cache.
                    if let freshPlan {
                        repository.savePlan(freshPlan)
                    } else {
                        repository.removePlan()
                    }
                } catch {
                    print("[CachedUserSettingsService] Background refresh failed. Keeping cached plan.")
                }
            }
            
            return localResult
            
        } else {
            // 3) If no cache or ignoring cache, fetch from the remote service directly
            let freshPlan = try await userSettingsService.fetchActivePlan(forUserId: userId)
            
            if let freshPlan {
                repository.savePlan(freshPlan)
            } else {
                repository.removePlan()
            }
            
            return freshPlan
        }
    }
    
    /// Forces a refresh from remote, ignoring cache. Throws if offline or the request fails.
    /// If `userId` is `nil`, returns `nil` because no remote fetch can occur.
    func refreshActivePlan(forUserId userId: UUID?) async throws -> Plan? {
        guard let userId = userId else {
            return nil
        }
        let freshPlan = try await userSettingsService.fetchActivePlan(forUserId: userId)
        
        if let freshPlan {
            repository.savePlan(freshPlan)
        } else {
            repository.removePlan()
        }
        
        return freshPlan
    }
    
    // MARK: - Remove local plan
    
    /// Removes the single cached plan
    func removeFromCache() {
        repository.removePlan()
    }
    
    /// Clears **all** locally cached user plans (though we only store one)
    func clearCache() {
        repository.removeAll()
        print("[CachedUserSettingsService] Cleared all user plan cache.")
    }
}
