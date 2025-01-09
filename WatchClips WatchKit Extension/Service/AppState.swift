//
//  AppState.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 27/12/2024.
//

import WatchKit

// MARK: - Shared App State
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var selectedVideo: Video?
    @Published var showDownloadList = false
}
