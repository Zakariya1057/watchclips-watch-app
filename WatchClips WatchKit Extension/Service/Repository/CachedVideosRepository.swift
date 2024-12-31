import Foundation
import SQLite3

final class CachedVideosRepository {
    static let shared = CachedVideosRepository()
    
    private init() {
        createTableIfNeeded()
    }
    
    // MARK: - Create Table
    /// Adds a `createdAt` column (of type REAL) to store the video's creation timestamp
    private func createTableIfNeeded() {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            // 1) Create table if not exists
            var sql = """
            CREATE TABLE IF NOT EXISTS CachedVideos(
                videoId TEXT PRIMARY KEY,
                code TEXT,
                createdAt REAL NOT NULL,
                json TEXT NOT NULL
            );
            """
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("CachedVideos table created or already exists.")
                } else {
                    print("Could not create CachedVideos table.")
                }
            } else {
                print("Create CachedVideos table statement could not be prepared.")
            }
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Save (Upsert) Videos
    /// Inserts or updates an array of `Video` objects into the CachedVideos table.
    /// Now also stores the `createdAt` value for proper sorting.
    func saveVideos(_ videos: [Video]) {
        for video in videos {
            insertOrReplaceVideo(video)
        }
    }
    
    private func insertOrReplaceVideo(_ video: Video) {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            // 1) Convert the `Video` to JSON
            guard let jsonData = try? JSONEncoder().encode(video),
                  let jsonString = String(data: jsonData, encoding: .utf8)
            else {
                print("Failed to encode Video to JSON for videoId: \(video.id)")
                return
            }
            
            // 2) Convert the `createdAt` to a timestamp (Double) for storage
            let createdAtTimestamp = video.createdAt.timeIntervalSince1970
            
            // 3) Upsert statement, now including the `createdAt` column
            let sql = """
            INSERT OR REPLACE INTO CachedVideos (videoId, code, createdAt, json)
            VALUES (?, ?, ?, ?);
            """
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                // videoId
                sqlite3_bind_text(statement, 1, (video.id as NSString).utf8String, -1, nil)
                // code
                sqlite3_bind_text(statement, 2, (video.code as NSString).utf8String, -1, nil)
                // createdAt
                sqlite3_bind_double(statement, 3, createdAtTimestamp)
                // json
                sqlite3_bind_text(statement, 4, (jsonString as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) != SQLITE_DONE {
                    print("Failed to insert/replace video with id \(video.id).")
                }
            } else {
                print("Could not prepare upsert statement for video with id \(video.id).")
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Load All Videos (Sorted by createdAt descending)
    /// Returns **all** videos from the DB, sorted by `createdAt` (newest first).
    func loadAllVideos() -> [Video] {
        return DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return [] }
            
            // ORDER BY createdAt DESC ensures newest -> oldest
            let sql = "SELECT json FROM CachedVideos ORDER BY createdAt DESC;"
            var statement: OpaquePointer?
            var results: [Video] = []
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let jsonCString = sqlite3_column_text(statement, 0) {
                        let jsonString = String(cString: jsonCString)
                        // Decode JSON back into a `Video`
                        if let jsonData = jsonString.data(using: .utf8),
                           let video = try? JSONDecoder().decode(Video.self, from: jsonData) {
                            results.append(video)
                        }
                    }
                }
            } else {
                print("SELECT statement could not be prepared for loadAllVideos().")
            }
            
            sqlite3_finalize(statement)
            return results
        }
    }
    
    // MARK: - Remove or Clear
    func removeVideoById(_ videoId: String) {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            let sql = "DELETE FROM CachedVideos WHERE videoId = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (videoId as NSString).utf8String, -1, nil)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }
    
    func removeAllVideos() {
        DatabaseHelper.shared.performDatabaseOperation { db in
            guard let db = db else { return }
            
            let sql = "DELETE FROM CachedVideos;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }
}
