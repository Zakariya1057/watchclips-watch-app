import Foundation

class StateManager: ObservableObject {
    @Published var isUserLoggedIn: Bool = UserDefaults.standard.bool(forKey: "isLoggedIn")

    func logout() {
        UserDefaults.standard.removeObject(forKey: "applicationId")
        UserDefaults.standard.set(false, forKey: "isLoggedIn")
        isUserLoggedIn = false
    }

    func login(applicationId: String) {
        UserDefaults.standard.set(applicationId, forKey: "applicationId")
        UserDefaults.standard.set(true, forKey: "isLoggedIn")
        isUserLoggedIn = true
    }
}
