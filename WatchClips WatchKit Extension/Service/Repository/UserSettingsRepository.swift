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
                userId TEXT PRIMARY KEY,
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
    /// Loads the `Plan` from the local DB for a given userId. Returns `nil` if not found or decoding fails.
    func loadPlan(for userId: String) -> Plan? {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return nil }
            
            let sql = "SELECT json FROM UserSettings WHERE userId = ? LIMIT 1;"
            var statement: OpaquePointer?
            var plan: Plan?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                // Bind userId
                sqlite3_bind_text(statement, 1, (userId as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    if let jsonCString = sqlite3_column_text(statement, 0) {
                        let jsonString = String(cString: jsonCString)
                        if let data = jsonString.data(using: .utf8) {
                            plan = try? JSONDecoder().decode(Plan.self, from: data)
                        }
                    }
                }
            } else {
                print("[UserSettingsRepository] SELECT statement could not be prepared for userId:", userId)
            }
            
            sqlite3_finalize(statement)
            return plan
        }
    }
    
    // MARK: - Save (Upsert) Plan
    /// Saves or updates the `Plan` (as JSON) in the local DB for `userId`.
    func savePlan(_ plan: Plan, for userId: String) {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            guard let jsonData = try? JSONEncoder().encode(plan),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                print("[UserSettingsRepository] JSON encoding failed for userId:", userId)
                return
            }
            
            let sql = """
            INSERT OR REPLACE INTO UserSettings (userId, json)
            VALUES (?, ?);
            """
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                // Bind userId
                sqlite3_bind_text(statement, 1, (userId as NSString).utf8String, -1, nil)
                // Bind JSON
                sqlite3_bind_text(statement, 2, (jsonString as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) != SQLITE_DONE {
                    print("[UserSettingsRepository] Insert/replace failed for userId:", userId)
                }
            } else {
                print("[UserSettingsRepository] Could not prepare statement for userId:", userId)
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Remove Plan
    func removePlan(for userId: String) {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            let sql = "DELETE FROM UserSettings WHERE userId = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (userId as NSString).utf8String, -1, nil)
                sqlite3_step(statement)
            } else {
                print("[UserSettingsRepository] DELETE statement could not be prepared for userId:", userId)
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
