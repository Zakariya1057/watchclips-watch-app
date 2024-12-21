//
//  VideoRow.swift
//  WatchClips Watch App
//
//  Created by Zakariya Hassan on 17/12/2024.
//

import SwiftUI

struct VideoRow: View {
    let video: Video
    let isDownloaded: Bool
    
    private let placeholderImageURL = "https://craftsnippets.com/articles_images/placeholder/placeholder.jpg"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CachedAsyncImage(
                url: URL(string: "https://dwxvsu8u3eeuu.cloudfront.net/\(video.image ?? "")")!
            ) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 150)
                    .clipped()
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(video.title ?? "Untitled Video")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(3)
                
                // Show a green "Downloaded" label if fully downloaded
                if isDownloaded {
                    Text("💾  Downloaded")
                        .font(.subheadline)
                        .foregroundColor(.green)
                } else {
                    Text("🌐  Streaming")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if let duration = video.duration {
                    Text("⏱  Duration: \(formattedDuration(duration))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text("📅  Uploaded: \(formattedDate(video.createdAt))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        // Add .id to re-render view when status changes
        .id(video.status)
    }
    
    private func formattedDuration(_ duration: Int) -> String {
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
