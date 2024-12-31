//
//  CodeItem.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//

import Foundation

struct Code: Decodable, Identifiable {
    let id: String
    let userId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
    }
}
