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
    /// Pass in a full `Video`. We'll encode its data into `userInfo` so we can retrieve
    /// it fully in `didReceive` (when the user taps the notification).
    func scheduleLocalNotification(title: String,
                                   body: String,
                                   video: Video,
                                   completion: @escaping (Bool) -> Void) {
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        // Convert dates to strings
        let dateFormatter = ISO8601DateFormatter()
        let createdAtString = dateFormatter.string(from: video.createdAt)
        let updatedAtString = dateFormatter.string(from: video.updatedAt)
        
        // Encode all the fields into userInfo
        // (userInfo must contain only property-list types: string, number, etc.)
        var userInfo: [String: Any] = [
            "id": video.id,
            "code": video.code,
            "filename": video.filename,
            "createdAt": createdAtString,
            "updatedAt": updatedAtString
        ]
        
        // Optionals
        if let title = video.title {
            userInfo["title"] = title
        }
        if let image = video.image {
            userInfo["image"] = image
        }
        if let url = video.url {
            userInfo["url"] = url
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
        
        // By default, watchOS does not show banners if app is foreground.
        // We force it to show a banner and play a sound:
        completionHandler([.banner, .sound])
    }
    
    /// Called when user taps a delivered notification (while app is in background or inactive).
    /// We read userInfo, parse a `Video`, and store it in `AppState.shared.selectedVideo`.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        
        let userInfo = response.notification.request.content.userInfo
        
        // We'll parse the userInfo dictionary back into a Video struct
        guard
            let id = userInfo["id"] as? String,
            let code = userInfo["code"] as? String,
            let filename = userInfo["filename"] as? String,
            let createdAtString = userInfo["createdAt"] as? String,
            let updatedAtString = userInfo["updatedAt"] as? String
        else {
            // If we can’t retrieve required fields, just return
            completionHandler()
            return
        }
        
        let title = userInfo["title"] as? String
        let image = userInfo["image"] as? String
        let url = userInfo["url"] as? String
        let size = userInfo["size"] as? Int64
        let duration = userInfo["duration"] as? Int
        
        // Convert `status` from raw string to enum
        var status: VideoStatus?
        if let statusRaw = userInfo["status"] as? String {
            status = VideoStatus(rawValue: statusRaw)
        }
        
        let processedSegments = userInfo["processed_segments"] as? Int
        let expectedSegments = userInfo["expected_segments"] as? Int
        
        // Decode dates from ISO8601 strings
        let dateFormatter = ISO8601DateFormatter()
        
        let createdAt = dateFormatter.date(from: createdAtString) ?? Date()
        let updatedAt = dateFormatter.date(from: updatedAtString) ?? Date()
        
        // Construct the full `Video`
        let tappedVideo = Video(
            id: id,
            code: code,
            title: title,
            image: image,
            filename: filename,
            url: url,
            size: size,
            duration: duration,
            createdAt: createdAt,
            updatedAt: updatedAt,
            status: status,
            processedSegments: processedSegments,
            expectedSegments: expectedSegments
        )
        
        // Update our app’s state on the main thread
        DispatchQueue.main.async {
            AppState.shared.selectedVideo = tappedVideo
        }
        
        completionHandler()
    }
}
