//
//  SettingsStore.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 09/01/2025.
//

import Foundation

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    
    // Our in-memory instance of AppSettings
    @Published var settings: AppSettings = .default
    
    private let repository = SettingsRepository.shared
    
    private init() {
        load()
    }
    
    /// Loads settings from DB. If none found, fall back to default.
    func load() {
        if let loaded = repository.loadSettings() {
            settings = loaded
        } else {
            settings = .default
        }
    }
    
    /// Saves current settings to DB.
    /// Call this after making changes to `settings`.
    func save() {
        repository.saveSettings(settings)
    }
    
    // MARK: - Example convenience access
    
    /// Toggle notifyOnDownload
    func setNotifyOnDownload(_ newValue: Bool) {
        settings.notifyOnDownload = newValue
        save()
    }
    
    // 2) Add method for resumeWhereLeftOff
    func setResumeWhereLeftOff(_ newValue: Bool) {
        settings.resumeWhereLeftOff = newValue
        save()
    }
}
