//
//  AppState+Extensions.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//

//
//  AppStorage+LoggedInState.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//

import SwiftUI

extension AppStorage where Value == Data {
    /// Helper to store/retrieve `LoggedInState` as JSON in AppStorage.
    func loggedInState(getDefault: @autoclosure () -> LoggedInState? = nil) -> LoggedInState? {
        // 1) Attempt to decode
        if let decoded = try? JSONDecoder().decode(LoggedInState.self, from: wrappedValue) {
            return decoded
        }
        // 2) If decode fails, return default
        return getDefault()
    }

    mutating func setLoggedInState(_ newValue: LoggedInState?) {
        if let newValue {
            let encoded = (try? JSONEncoder().encode(newValue)) ?? Data()
            wrappedValue = encoded
        } else {
            // If you want to "clear" it, set empty data or something
            wrappedValue = Data()
        }
    }
}
