import SwiftUI

struct VideoRow: View {
    let video: Video
    let isDownloaded: Bool
    
    // Apple Watch–friendly, "hype" status messages
    private func getStatusDisplay(_ status: VideoStatus?) -> (message: String, color: Color, isLoading: Bool) {
        guard let status = status else {
            return ("Gearing up...", .blue, true)
        }
        
        switch status {
        case .preProcessing, .processing, .chunking, .processingChunk:
            // Early/middle processing
            return ("Gearing up...", .blue, true)
        case .chunkingComplete, .chunkProcessed:
            // Late processing
            return ("Polishing...", .blue, true)
        case .postProcessingSuccess:
            // Completed successfully
            return ("Time to watch!", .green, false)
        case .postProcessingFailure, .chunkingFailure, .chunkProcessingFailure:
            // Errors
            return ("Oh no!", .red, false)
        }
    }
    
    var body: some View {
        let statusInfo = getStatusDisplay(video.status)
        
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .center) {
                if video.status == .postProcessingSuccess {
                    // If fully processed, show the thumbnail
                    CachedAsyncImage(
                        url: URL(string: "https://dwxvsu8u3eeuu.cloudfront.net/\(video.image ?? "")")!
                    ) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .clipped()
                    }
                } else {
                    // Semi-opaque overlay + centered status
                    Rectangle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: .infinity, height: 150)
                    
                    VStack(spacing: 4) {
                        if statusInfo.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: statusInfo.color))
                        }
                        Text(statusInfo.message)
                            .font(.caption)
                            .foregroundColor(statusInfo.color)
                    }
                    .frame(width: .infinity, height: 60)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 150)
            
            // Video info below the thumbnail
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
                    .lineLimit(nil) // Allows unlimited lines
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .id(video.status) // re-render if status changes
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
