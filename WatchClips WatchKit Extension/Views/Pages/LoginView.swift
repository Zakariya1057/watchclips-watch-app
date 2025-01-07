import SwiftUI
import Supabase

struct LoginView: View {
    @State private var code = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showHelpAlert = false

    @AppStorage("loggedInState") private var loggedInStateData = Data()

    private var codesService: CodeService { CodeService(client: supabase) }
    private var userSettingsService: UserSettingsService { UserSettingsService(client: supabase) }

    var body: some View {
        ZStack {
            Form {
                Section(header: Text("Enter Your Code")) {
                    TextField("Code from website", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                Section {
                    Button(action: signInButtonTapped) {
                        HStack {
                            Spacer()
                            Text("Login")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .handGestureShortcut(.primaryAction)
                    .disabled(code.isEmpty)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            // 1) Add a Toolbar with the Help button in the top-right
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("WatchClips")
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("?") {
                        showHelpAlert = true
                    }
                }
            }

            // Full-screen loading overlay
            if isLoading {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                ProgressView("Checking code...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    .foregroundColor(.white)
            }
        }
        // Alert for errors
        .alert("Error", isPresented: Binding<Bool>(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Close", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        // Alert for Help
        .alert("Need Help?", isPresented: $showHelpAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To get your login code, please visit WatchClips.app")
        }
    }

    func signInButtonTapped() {
        Task {
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }

            do {
                let codeRecord = try await codesService.fetchCode(byId: code)
                var plan: Plan? = nil
                if let userUUID = codeRecord.userId {
                    plan = try? await userSettingsService.fetchActivePlan(forUserId: userUUID)
                }
                let newState = LoggedInState(code: codeRecord.id, userId: codeRecord.userId, activePlan: plan)
                let encoded = try JSONEncoder().encode(newState)
                loggedInStateData = encoded

            } catch {
                handleError(error)
            }
        }
    }

    private func handleError(_ error: Error) {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                errorMessage = "No internet connection. Please check your network and try again."
            case .timedOut:
                errorMessage = "The request timed out. Please try again later."
            case .cannotFindHost, .cannotConnectToHost:
                errorMessage = "Unable to reach the server. Please try again."
            default:
                errorMessage = "A network error occurred. Please try again."
            }
        } else {
            errorMessage = "Code not found or invalid. Please check the code from WatchClips website."
        }
    }
}
