import SwiftUI

struct ContentView: Scene {
    @AppStorage("loggedInCode") private var loggedInCode: String = ""
    
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if loggedInCode.isEmpty {
                    LoginView()
                } else {
                    VideoListView(code: loggedInCode)
                }
            }
        }
    }
}
