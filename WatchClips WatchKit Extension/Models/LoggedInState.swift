//
//  LoggedInState.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//

import Foundation

struct LoggedInState: Codable, Equatable, Identifiable {
    var id: String { code }  // or any unique property

    let code: String       // The code the user entered
    let userId: UUID?      // E.g. if the code is associated with a user
    
    // NEW: Store the entire Plan (includes the 'features' field)
    var activePlan: Plan?
    
    // Optional: convenience initializer
    init(code: String,
         userId: UUID? = nil,
         activePlan: Plan? = nil)
    {
        self.code = code
        self.userId = userId
        self.activePlan = activePlan
    }
}
