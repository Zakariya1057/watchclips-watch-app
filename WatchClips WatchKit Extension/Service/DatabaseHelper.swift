//
//  DatabaseHelper.swift
//  WatchClips
//

import Foundation
import SQLite3

final class DatabaseHelper {
    static let shared = DatabaseHelper()
    
    /// A serial queue that ensures only one database operation happens at a time
    private let dbQueue = DispatchQueue(label: "com.yourapp.DatabaseHelperQueue")
    
    private var db: OpaquePointer?

    private init() {
        db = openDatabase()
    }
    
    // MARK: - Database Path
    private func databasePath() -> String? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDirectory
            .appendingPathComponent("AppDatabase.sqlite")
            .path
    }
    
    // MARK: - Open Database
    private func openDatabase() -> OpaquePointer? {
        guard let path = databasePath() else { return nil }
        
        var dbPointer: OpaquePointer?
        if sqlite3_open(path, &dbPointer) == SQLITE_OK {
            print("Successfully opened database at \(path)")
            return dbPointer
        } else {
            print("Failed to open database.")
            return nil
        }
    }

    // MARK: - Perform Database Operation
    /// Call this from your repository classes to ensure thread-safe operations.
    func performDatabaseOperation<T>(_ block: (OpaquePointer?) -> T) -> T {
        return dbQueue.sync {
            block(db)
        }
    }

    // MARK: - Close
    deinit {
        if let db = db {
            if sqlite3_close(db) == SQLITE_OK {
                print("Database closed successfully.")
            } else {
                print("Error closing the database.")
            }
        }
    }
}
