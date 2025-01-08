//
//  EncodeLoggedInState.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//
import SwiftUI

/// Encodes a `LoggedInState` into JSON `Data`.
/// - Parameter state: The `LoggedInState` instance to encode.
/// - Returns: JSON-encoded `Data`, or `nil` if encoding fails.
func encodeLoggedInState(_ state: LoggedInState) -> Data? {
    do {
        let encoder = JSONEncoder()
        return try encoder.encode(state)
    } catch {
        print("Failed to encode LoggedInState:", error)
        return nil
    }
}
