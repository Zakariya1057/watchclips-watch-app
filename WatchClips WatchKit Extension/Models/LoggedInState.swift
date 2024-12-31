//
//  LoggedInState.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//

import Foundation

struct LoggedInState: Codable, Equatable, Identifiable {
    var id: String { code }  // or any unique property

    let code: String          // The code the user entered
    let userId: UUID?       // E.g. if the code is associated with a user
    var planName: PlanName?     // Or any other fields you might want to store
    // add more fields as you see fit:
    // let expiresAt: Date?
    // let planFeatures: [String: Any]?

    // Optional: convenience initializer, if needed
    init(code: String, userId: UUID? = nil, planName: PlanName? = nil) {
        self.code = code
        self.userId = userId
        self.planName = planName
    }
}
