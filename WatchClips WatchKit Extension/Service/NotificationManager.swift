import Foundation
import UserNotifications
import WatchKit

/// A singleton class responsible for requesting notification authorization
/// and scheduling local notifications on watchOS.
class NotificationManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    static let shared = NotificationManager()
    
    private override init() {
        super.init()
        // 1) Set ourselves as the UNUserNotificationCenter delegate
        UNUserNotificationCenter.current().delegate = self
    }
    
    // MARK: - Request Authorization
    /// Request the user’s permission for alert and sound notifications.
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
    /// Schedules a local notification on watchOS with a custom title and body.
    /// The notification will be triggered almost immediately.
    ///
    /// - Parameters:
    ///   - title: The notification title (e.g., "Reminder").
    ///   - body: The notification body text (e.g., "It’s time to check your app.").
    ///   - completion: A closure called when scheduling is complete.
    ///                 Passes `true` if scheduling succeeded, or `false` if there was an error.
    func scheduleLocalNotification(title: String,
                                   body: String,
                                   completion: @escaping (Bool) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        // Use a minimal time interval to simulate an "immediate" notification.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: trigger)
        
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
    
    /// Called when a notification arrives *while* the app is in the foreground.
    /// Use this to tell watchOS to still show a banner/alert/sound, etc.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        
        // By default, watchOS won't show alerts if the app is foreground.
        // Force it to show an alert banner and play a sound:
        completionHandler([.banner, .sound])
    }
}
