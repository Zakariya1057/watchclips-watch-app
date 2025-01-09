import Foundation
import UserNotifications
import WatchKit

class NotificationManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    static let shared = NotificationManager()
    
    private override init() {
        super.init()
        // Set ourselves as the UNUserNotificationCenter delegate
        UNUserNotificationCenter.current().delegate = self
    }
    
    // MARK: - Request Authorization
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Authorization error: \(error.localizedDescription)")
            } else {
                print("Authorization granted: \(granted)")
            }
        }
    }
    
    // MARK: - Schedule Notification (Immediate)
    /// Pass in:
    /// - `action`: determines what happens when user taps the notification.
    /// - A full `Video`.
    /// We'll store these in `userInfo` so we can retrieve them in `didReceive`.
    func scheduleLocalNotification(
        title: String,
        body: String,
        video: Video,
        action: NotificationAction,   // <-- New parameter
        completion: @escaping (Bool) -> Void
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        // Convert dates to strings
        let dateFormatter = ISO8601DateFormatter()
        let createdAtString = dateFormatter.string(from: video.createdAt)
        let updatedAtString = dateFormatter.string(from: video.updatedAt)
        
        // Prepare userInfo with all the fields
        var userInfo: [String: Any] = [
            "id": video.id,
            "code": video.code,
            "filename": video.filename,
            "createdAt": createdAtString,
            "updatedAt": updatedAtString,
            "actionToPerform": action.rawValue  // <-- Store the action here
        ]
        
        // Optionals
        if let title = video.title {
            userInfo["title"] = title
        }
        if let image = video.image {
            userInfo["image"] = image
        }
        if let size = video.size {
            userInfo["size"] = size
        }
        if let duration = video.duration {
            userInfo["duration"] = duration
        }
        if let status = video.status?.rawValue {
            userInfo["status"] = status
        }
        if let processedSegments = video.processedSegments {
            userInfo["processed_segments"] = processedSegments
        }
        if let expectedSegments = video.expectedSegments {
            userInfo["expected_segments"] = expectedSegments
        }

        userInfo["is_optimizing"] = video.isOptimizing
        
        content.userInfo = userInfo
        
        // Minimal time interval to simulate an "immediate" notification
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
                completion(false)
            } else {
                print("Notification scheduled successfully.")
                completion(true)
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    
    /// Called when a notification arrives while the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        
        // By default, watchOS might not show banners if foreground.
        // Force it to show a banner and play a sound:
        completionHandler([.banner, .sound])
    }
    
    /// Called when user taps a delivered notification.
    /// We parse the `userInfo` to see which action to take.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        
        let userInfo = response.notification.request.content.userInfo
        
        // First, parse out the action
        guard let actionRaw = userInfo["actionToPerform"] as? String,
              let action = NotificationAction(rawValue: actionRaw) else {
            // If no action is specified, default behavior
            completionHandler()
            return
        }
        
        // Parse the rest of the userInfo to rebuild a Video (optional, if you need it)
        guard
            let id = userInfo["id"] as? String,
            let code = userInfo["code"] as? String,
            let filename = userInfo["filename"] as? String,
            let createdAtString = userInfo["createdAt"] as? String,
            let updatedAtString = userInfo["updatedAt"] as? String
        else {
            completionHandler()
            return
        }
        
        let title = userInfo["title"] as? String
        let image = userInfo["image"] as? String
        let size = userInfo["size"] as? Int64
        let duration = userInfo["duration"] as? Int
        let processedSegments = userInfo["processed_segments"] as? Int
        let expectedSegments = userInfo["expected_segments"] as? Int
        let isOptimizing = userInfo["is_optimizing"] as? Bool
        
        // Convert `status` from raw string to enum
        var status: VideoStatus?
        if let statusRaw = userInfo["status"] as? String {
            status = VideoStatus(rawValue: statusRaw)
        }
        
        // Decode dates from ISO8601 strings
        let dateFormatter = ISO8601DateFormatter()
        let createdAt = dateFormatter.date(from: createdAtString) ?? Date()
        let updatedAt = dateFormatter.date(from: updatedAtString) ?? Date()
        
        // Construct a `Video` if needed
        let tappedVideo = Video(
            id: id,
            code: code,
            title: title,
            image: image,
            filename: filename,
            size: size,
            duration: duration,
            createdAt: createdAt,
            updatedAt: updatedAt,
            status: status,
            processedSegments: processedSegments,
            expectedSegments: expectedSegments,
            isOptimizing: isOptimizing ?? false
        )
        
        // Decide what to do based on the action
        DispatchQueue.main.async {
            switch action {
            case .openDownloads:
                // For instance, you might set a flag to show the Downloads screen
                // or navigate to a "DownloadsList" view in your app state.
                AppState.shared.showDownloadList = true
                // Clear any previously selected video
                AppState.shared.selectedVideo = nil
                
            case .openVideoPlayer:
                // Set the selectedVideo to open it
                AppState.shared.selectedVideo = tappedVideo
                AppState.shared.showDownloadList = false
            }
        }
        
        completionHandler()
    }
}
