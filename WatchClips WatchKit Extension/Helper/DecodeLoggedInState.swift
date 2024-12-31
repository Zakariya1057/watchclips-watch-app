//
//  DecodeLoggedInState.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//
import SwiftUI

func decodeLoggedInState(from data: Data) -> LoggedInState? {
    guard !data.isEmpty else { return nil }
    return try? JSONDecoder().decode(LoggedInState.self, from: data)
}
