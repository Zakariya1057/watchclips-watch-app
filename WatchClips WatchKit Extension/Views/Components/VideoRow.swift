import SwiftUI

struct VideoRow: View {
    let video: Video
    let isDownloaded: Bool
    
    // Shorter “hype” messages for watch screens
    private func getStatusDisplay(_ status: VideoStatus?) -> (message: String, color: Color, isLoading: Bool) {
        guard let status = status else {
            return ("Processing...", .gray, true)
        }
        
        switch status {
        // Early or mid processing
        case .preProcessing, .processing, .chunking, .processingChunk:
            return ("Optimizing...", .blue, true)
        // Late processing
        case .chunkingComplete, .chunkProcessed:
            return ("Almost done...", .blue, true)
        // Completed successfully
        case .postProcessingSuccess:
            return ("Watch ready!", .green, false)
        // Errors
        case .postProcessingFailure, .chunkingFailure, .chunkProcessingFailure:
            return ("Failed", .red, false)
        }
    }
    
    var body: some View {
        let statusInfo = getStatusDisplay(video.status)
        
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .center) {
                // 1) If fully processed => show thumbnail
                if video.status == .postProcessingSuccess {
                    CachedAsyncImage(
                        url: URL(string: "https://dwxvsu8u3eeuu.cloudfront.net/\(video.image ?? "")")!
                    ) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .clipped()
                    }
                } else {
                    // 2) Show overlay & either a circular progress or fallback
                    Rectangle()
                        .fill(Color.black.opacity(0.3))
                        .frame(maxWidth: .infinity, maxHeight: 150)

                    // If we have valid segment data, display progress circle
                    if let processed = video.processedSegments,
                       let expected = video.expectedSegments,
                       expected > 0
                    {
                        let fraction = Double(processed) / Double(expected+1)
                        
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
                            }.padding(.bottom, 10)
                            
                            Text("Processing")
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                        .frame(width: .infinity, height: 150)
                    } else {
                        // Fallback: simple spinner + message
                        VStack(spacing: 0) { // <— Set spacing to whatever smaller value you want
                            ProgressView()
                                .progressViewStyle(
                                    CircularProgressViewStyle(tint: statusInfo.color)
                                )
                                .frame(width: .infinity, height: 10)
                                .padding(.bottom, 10)
                            
                            Text(statusInfo.message)
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                        .frame(width: .infinity, height: 150)
                    }
                }
            }
            .frame(width: .infinity, height: 150)
            
            // 3) Video info below
            VStack(alignment: .leading, spacing: 6) {
                Text(video.title ?? "Untitled")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(3)
                
                if isDownloaded {
                    Text("💾 Downloaded")
                        .font(.subheadline)
                        .foregroundColor(.green)
                } else {
                    Text("🌐 Streaming")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if let duration = video.duration {
                    Text("⏱ \(formattedDuration(duration))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text("📅 \(formattedDate(video.createdAt))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        // Re-render if status changes
        .id(video.status)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            // e.g. "Today at 11:05"
            return "Today at " + formattedTime(date)
        } else if calendar.isDateInYesterday(date) {
            // e.g. "Yesterday at 12:05"
            return "Yesterday at " + formattedTime(date)
        } else {
            // e.g. "11:05 PM at Jan 14, 2024"
            let time = formattedTime(date)
            let dateString = formattedDateString(date)
            return "\(dateString) at \(time)"
        }
    }

    // MARK: - Helpers

    /// Returns a short time format, e.g. "3:45 PM"
    private func formattedTime(_ date: Date) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        return timeFormatter.string(from: date)
    }

    /// Returns a medium date format, e.g. "Jan 14, 2024"
    private func formattedDateString(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        return dateFormatter.string(from: date)
    }
    
    private func formattedDuration(_ duration: Int) -> String {
        // Convert total seconds into hours, minutes, seconds
        let hours = duration / 3600
        let leftover = duration % 3600
        let minutes = leftover / 60
        let seconds = leftover % 60
        
        if hours > 0 {
            // If there's at least 1 hour, show HH:MM:SS
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            // Otherwise, just show MM:SS
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
