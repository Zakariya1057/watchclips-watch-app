import SwiftUI

struct VideoRow: View {
    let video: Video
    let isDownloaded: Bool
    let watchProgress: Double?
    
    private func getStatusDisplay(_ status: VideoStatus?) -> (message: String, color: Color, isLoading: Bool) {
        guard let status = status else {
            return ("Processing...", .gray, true)
        }
        
        switch status {
        case .preProcessing, .processing, .chunking, .processingChunk:
            return ("Optimizing...", .blue, true)
        case .finalizing:
            return ("Finalizing...", .orange, true)
        case .chunkingComplete, .chunkProcessed:
            return ("Almost done...", .blue, true)
        case .postProcessingSuccess:
            return ("Watch ready!", .green, false)
        case .postProcessingFailure, .chunkingFailure, .chunkProcessingFailure:
            return ("Failed", .red, false)
        }
    }
    
    var body: some View {
        let statusInfo = getStatusDisplay(video.status)
        
        VStack(alignment: .leading, spacing: 4) {
            
            // 1) Use .bottomLeading for the main ZStack alignment
            ZStack(alignment: .bottomLeading) {
                
                if video.status == .postProcessingSuccess {
                    // 2) Fix the thumbnail's height so there's guaranteed space
                    CachedAsyncImage(
                        url: URL(string: "https://dwxvsu8u3eeuu.cloudfront.net/\(video.image ?? "")")!,
                        height: 100
                    ) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(height: 100)
                            .clipped()
                    }
                    
                    if let watchProgress = watchProgress {
                        // 3) The progress bar overlay is now at the bottom
                        WatchProgressBar(
                            watchProgress: watchProgress,
                            totalDuration: Double(video.duration ?? 0)
                        )
                    }
                } else {
                    // Non-finished thumbnail placeholder/spinner
                    Rectangle()
                        .fill(Color.black.opacity(0.3))
                        .frame(height: 100)
                    
                    if let processed = video.processedSegments,
                       let expected = video.expectedSegments,
                       expected > 0
                    {
                        let fraction = Double(processed) / Double(expected + 1)
                        
                        VStack {
                            ZStack {
                                Circle()
                                    .stroke(lineWidth: 6)
                                    .foregroundColor(.white.opacity(0.2))
                                    .frame(width: 60, height: 60)
                                
                                Circle()
                                    .trim(from: 0, to: fraction)
                                    .stroke(
                                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                                    )
                                    .foregroundColor(statusInfo.color)
                                    .frame(width: 60, height: 60)
                                    .rotationEffect(.degrees(-90))
                                
                                Text("\(Int(fraction * 100))%")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            .padding(.bottom, 10)
                            
                            Text("Processing")
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                        
                    } else {
                        // Fallback spinner + message
                        VStack(spacing: 0) {
                            ProgressView()
                                .progressViewStyle(
                                    CircularProgressViewStyle(tint: statusInfo.color)
                                )
                                .frame(maxWidth: .infinity, minHeight: 10, maxHeight: 10)
                                .padding(.bottom, 10)
                            
                            Text(statusInfo.message)
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                    }
                }
            }
            // Force the ZStack to fill the width and have fixed height
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            
            // Video info below
            VStack(alignment: .leading, spacing: 6) {
                Text(video.title ?? "Untitled")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(3)
                
                if isDownloaded {
                    Text("💾 Downloaded")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
                
                if let duration = video.duration {
                    Text("🕒 \(formattedDuration(duration))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text("📅 \(formattedDate(video.createdAt))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .id(video.status) // Re-render if status changes
    }
    
    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            return "Today at " + formattedTime(date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday at " + formattedTime(date)
        } else {
            let time = formattedTime(date)
            let dateString = formattedDateString(date)
            return "\(dateString) at \(time)"
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        return timeFormatter.string(from: date)
    }

    private func formattedDateString(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        return dateFormatter.string(from: date)
    }
    
    private func formattedDuration(_ duration: Int) -> String {
        let hours = duration / 3600
        let leftover = duration % 3600
        let minutes = leftover / 60
        let seconds = leftover % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
