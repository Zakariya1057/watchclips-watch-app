//
//  AppSettings.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 09/01/2025.
//

import Foundation

struct AppSettings: Codable {
    var notifyOnDownload: Bool
    
    // 1) Add Resume Where Left Off
    var resumeWhereLeftOff: Bool
    
    // Provide a default instance for first-time loads
    static let `default` = AppSettings(
        notifyOnDownload: true,
        resumeWhereLeftOff: true
    )
}
