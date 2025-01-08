//
//  UserSettingsRepository.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//

import Foundation
import SQLite3

final class UserSettingsRepository {
    static let shared = UserSettingsRepository()
    
    private init() {
        createTableIfNeeded()
    }
    
    // MARK: - Create Table
    private func createTableIfNeeded() {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            let sql = """
            CREATE TABLE IF NOT EXISTS UserSettings (
                id INTEGER PRIMARY KEY,
                json TEXT NOT NULL
            );
            """
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("[UserSettingsRepository] Table created or already exists.")
                } else {
                    print("[UserSettingsRepository] Could not create table.")
                }
            } else {
                print("[UserSettingsRepository] CREATE TABLE statement could not be prepared.")
            }
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Load Plan
    /// Loads the single `Plan` from the local DB. Returns `nil` if not found or if decoding fails.
    func loadPlan() -> Plan? {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return nil }
            
            let sql = "SELECT json FROM UserSettings WHERE id = 1 LIMIT 1;"
            var statement: OpaquePointer?
            var plan: Plan?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    if let jsonCString = sqlite3_column_text(statement, 0) {
                        let jsonString = String(cString: jsonCString)
                        if let data = jsonString.data(using: .utf8) {
                            plan = try? JSONDecoder().decode(Plan.self, from: data)
                        }
                    }
                }
            } else {
                print("[UserSettingsRepository] SELECT statement could not be prepared.")
            }
            
            sqlite3_finalize(statement)
            return plan
        }
    }
    
    // MARK: - Save (Upsert) Plan
    /// Saves or updates the single `Plan` (as JSON) in the local DB.
    func savePlan(_ plan: Plan) {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            guard let jsonData = try? JSONEncoder().encode(plan),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                print("[UserSettingsRepository] JSON encoding failed.")
                return
            }
            
            let sql = """
            INSERT OR REPLACE INTO UserSettings (id, json)
            VALUES (1, ?);
            """
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                // Bind JSON
                sqlite3_bind_text(statement, 1, (jsonString as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) != SQLITE_DONE {
                    print("[UserSettingsRepository] Insert/replace failed.")
                }
            } else {
                print("[UserSettingsRepository] Could not prepare statement.")
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Remove Plan
    func removePlan() {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            let sql = "DELETE FROM UserSettings WHERE id = 1;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_step(statement)
            } else {
                print("[UserSettingsRepository] DELETE statement could not be prepared.")
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Remove All
    func removeAll() {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            let sql = "DELETE FROM UserSettings;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }
}
