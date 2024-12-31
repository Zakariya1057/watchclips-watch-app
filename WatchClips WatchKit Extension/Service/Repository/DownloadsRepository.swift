//
//  DownloadsRepository.swift
//  WatchClips
//

import Foundation
import SQLite3

final class DownloadsRepository {
    static let shared = DownloadsRepository()
    
    private init() {
        createTableIfNeeded()
    }
    
    // MARK: - Create Table
    private func createTableIfNeeded() {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            let sql = """
            CREATE TABLE IF NOT EXISTS Downloads(
                videoId TEXT PRIMARY KEY,
                json TEXT NOT NULL
            );
            """
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("Downloads table created or already exists.")
                } else {
                    print("Could not create Downloads table.")
                }
            } else {
                print("CREATE TABLE statement could not be prepared for Downloads.")
            }
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Load All Downloads
    /// Returns **all** DownloadedVideo objects from the DB, or an empty array if none.
    func loadAll() -> [DownloadedVideo] {
        return DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return [] }
            
            let sql = "SELECT json FROM Downloads;"
            var statement: OpaquePointer?
            var results: [DownloadedVideo] = []
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let jsonCString = sqlite3_column_text(statement, 0) {
                        let jsonString = String(cString: jsonCString)
                        
                        // Decode the JSON into a `DownloadedVideo`
                        if let data = jsonString.data(using: .utf8),
                           let downloadedVideo = try? JSONDecoder().decode(DownloadedVideo.self, from: data) {
                            results.append(downloadedVideo)
                        }
                    }
                }
            } else {
                print("SELECT statement could not be prepared for Downloads table.")
            }
            
            sqlite3_finalize(statement)
            return results
        }
    }
    
    // MARK: - Save (Upsert) Downloads
    /// Saves an array of `DownloadedVideo` objects (insert or replace).
    func saveAll(_ downloads: [DownloadedVideo]) {
        // Similar logic: Up to you if you want to batch them in one transaction or do them individually
        for item in downloads {
            insertOrReplace(item)
        }
    }
    
    private func insertOrReplace(_ downloadedVideo: DownloadedVideo) {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            // Encode the `DownloadedVideo` as JSON
            guard let jsonData = try? JSONEncoder().encode(downloadedVideo),
                  let jsonString = String(data: jsonData, encoding: .utf8)
            else {
                print("[DownloadsRepository] JSON encoding failed for videoId: \(downloadedVideo.id)")
                return
            }
            
            let sql = """
            INSERT OR REPLACE INTO Downloads (videoId, json)
            VALUES (?, ?);
            """
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (downloadedVideo.id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (jsonString as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) != SQLITE_DONE {
                    print("[DownloadsRepository] Insert/replace failed for videoId: \(downloadedVideo.id)")
                }
            } else {
                print("[DownloadsRepository] Could not prepare statement for videoId: \(downloadedVideo.id).")
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Remove All
    func removeAll() {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            let sql = "DELETE FROM Downloads;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Remove by ID
    func removeById(_ videoId: String) {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            let sql = "DELETE FROM Downloads WHERE videoId = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (videoId as NSString).utf8String, -1, nil)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }
}
