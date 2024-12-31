//
//  PlaybackProgressRepository.swift
//  WatchClips
//

import Foundation
import SQLite3

final class PlaybackProgressRepository {
    static let shared = PlaybackProgressRepository()
    
    private init() {
        // Moved table creation into a single call:
        createTableIfNeeded()
    }
    
    // MARK: - Create Table
    private func createTableIfNeeded() {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            let sql = """
            CREATE TABLE IF NOT EXISTS PlaybackProgress(
                VideoID TEXT PRIMARY KEY,
                Progress REAL NOT NULL,
                UpdatedAt REAL NOT NULL
            );
            """
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("PlaybackProgress table created or already exists.")
                } else {
                    print("Could not create PlaybackProgress table.")
                }
            } else {
                print("Create PlaybackProgress table statement could not be prepared.")
            }
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Insert or Update
    func setProgress(videoId: String, progress: Double, updatedAt: Double) {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            let sql = """
            INSERT OR REPLACE INTO PlaybackProgress (VideoID, Progress, UpdatedAt)
            VALUES (?, ?, ?);
            """
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (videoId as NSString).utf8String, -1, nil)
                sqlite3_bind_double(statement, 2, progress)
                sqlite3_bind_double(statement, 3, updatedAt)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("Successfully inserted/updated progress for video: \(videoId)")
                } else {
                    print("Failed to insert/replace data for video: \(videoId)")
                }
            } else {
                print("Upsert statement could not be prepared for video: \(videoId).")
            }
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Fetch
    func getProgress(videoId: String) -> (progress: Double, updatedAt: Double)? {
        return DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return nil }
            
            let sql = """
            SELECT Progress, UpdatedAt
            FROM PlaybackProgress
            WHERE VideoID = ?;
            """
            
            var statement: OpaquePointer?
            var result: (Double, Double)?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (videoId as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    let progress = sqlite3_column_double(statement, 0)
                    let updatedAt = sqlite3_column_double(statement, 1)
                    result = (progress, updatedAt)
                }
            } else {
                print("SELECT statement could not be prepared for video: \(videoId).")
            }
            
            sqlite3_finalize(statement)
            return result
        }
    }
    
    // MARK: - Fetch Most Recent
    func getMostRecentlyUpdatedVideoId() -> String? {
        return DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return nil }
            
            let sql = """
            SELECT VideoID
            FROM PlaybackProgress
            ORDER BY UpdatedAt DESC
            LIMIT 1;
            """
            
            var statement: OpaquePointer?
            var mostRecentId: String?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_ROW {
                    if let cString = sqlite3_column_text(statement, 0) {
                        mostRecentId = String(cString: cString)
                    }
                }
            } else {
                print("SELECT statement could not be prepared for most recent video.")
            }
            
            sqlite3_finalize(statement)
            return mostRecentId
        }
    }
    
    // MARK: - Delete
    func clearProgress(videoId: String) {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            let sql = "DELETE FROM PlaybackProgress WHERE VideoID = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (videoId as NSString).utf8String, -1, nil)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }
    
    func clearAllProgress() {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            let sql = "DELETE FROM PlaybackProgress;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }
}
