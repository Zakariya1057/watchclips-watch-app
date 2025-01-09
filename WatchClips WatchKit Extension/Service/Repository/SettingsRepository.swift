//
//  SettingsRepository.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 09/01/2025.
//


import Foundation
import SQLite3

final class SettingsRepository {
    static let shared = SettingsRepository()
    
    private init() {
        createTableIfNeeded()
    }
    
    // MARK: - Create Table
    private func createTableIfNeeded() {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            let sql = """
            CREATE TABLE IF NOT EXISTS Settings(
                key TEXT PRIMARY KEY,
                json TEXT NOT NULL
            );
            """
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("[SettingsRepository] 'Settings' table created or already exists.")
                } else {
                    print("[SettingsRepository] Could not create 'Settings' table.")
                }
            } else {
                print("[SettingsRepository] CREATE TABLE statement could not be prepared.")
            }
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Load Settings
    /// Attempts to load the AppSettings from the `Settings` table under key="appSettings".
    /// Returns nil if no row found or if decoding failed.
    func loadSettings() -> AppSettings? {
        return DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return nil }
            
            let sql = "SELECT json FROM Settings WHERE key = 'appSettings' LIMIT 1;"
            var statement: OpaquePointer?
            var loadedSettings: AppSettings? = nil
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_ROW {
                    if let jsonCString = sqlite3_column_text(statement, 0) {
                        let jsonString = String(cString: jsonCString)
                        if let data = jsonString.data(using: .utf8),
                           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
                            loadedSettings = decoded
                        } else {
                            print("[SettingsRepository] Failed to decode AppSettings from JSON.")
                        }
                    }
                }
            } else {
                print("[SettingsRepository] SELECT statement could not be prepared for 'Settings'.")
            }
            
            sqlite3_finalize(statement)
            return loadedSettings
        }
    }
    
    // MARK: - Save Settings
    /// Upserts the entire `AppSettings` object as JSON into the `Settings` table.
    func saveSettings(_ settings: AppSettings) {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            guard let jsonData = try? JSONEncoder().encode(settings),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                print("[SettingsRepository] JSON encoding failed for AppSettings.")
                return
            }
            
            let sql = """
            INSERT OR REPLACE INTO Settings (key, json)
            VALUES ('appSettings', ?);
            """
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                // Bind the JSON string
                sqlite3_bind_text(statement, 1, (jsonString as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) != SQLITE_DONE {
                    print("[SettingsRepository] Insert/replace failed for 'appSettings'.")
                }
            } else {
                print("[SettingsRepository] Could not prepare statement for saving settings.")
            }
            
            sqlite3_finalize(statement)
        }
    }
}
