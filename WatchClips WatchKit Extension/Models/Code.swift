//
//  Code.swift
//  WatchClips Watch App
//
//  Created by Zakariya Hassan on 12/12/2024.
//

import Foundation

struct Code: Identifiable, Codable {
    let id: String
    let ipAddress: String?
    let expiresAt: Date?
    let lastAccessedAt: Date
    let accessCount: Int
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case ipAddress = "ip_address"
        case expiresAt = "expires_at"
        case lastAccessedAt = "last_accessed_at"
        case accessCount = "access_count"
        case createdAt = "created_at"
    }
}
