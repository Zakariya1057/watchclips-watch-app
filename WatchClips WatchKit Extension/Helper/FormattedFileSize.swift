//
//  FormattedFileSize.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 08/01/2025.
//


/// Converts bytes to "XXX.X MB" or "YYY.Y KB"
func formattedFileSize(_ bytes: Int64) -> String {
    let kb = Double(bytes) / 1024.0
    if kb < 1024.0 {
        // Show in KB
        return String(format: "%.1f KB", kb)
    } else {
        // Show in MB
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }
}
