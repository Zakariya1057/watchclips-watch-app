import SwiftUI
import Supabase

struct LoginView: View {
    @State private var code = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Instead of just storing the code string, we store the entire state as Data
    @AppStorage("loggedInState") private var loggedInStateData = Data()

    private var codesService: CodeService {
        CodeService(client: supabase)
    }

    // Access your userSettingsService to fetch plan info
    private var userSettingsService: UserSettingsService {
        UserSettingsService(client: supabase)
    }

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
            .navigationTitle("WatchClips")
            .navigationBarTitleDisplayMode(.inline)

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
        .alert("Error", isPresented: Binding<Bool>(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Close", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    /// Invoked when the user taps “Login.”
    func signInButtonTapped() {
        Task {
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }

            do {
                // 1) Fetch the Code record from the DB
                let codeRecord = try await codesService.fetchCode(byId: code)
                print("Code found: \(codeRecord.id)")
                
                // 2) If codeRecord.userId is set, fetch the plan for that user
                var planName: PlanName? = nil
                if let userUUID = codeRecord.userId {
                    // Safely try fetching the plan
                    if let plan = try? await userSettingsService.fetchActivePlan(forUserId: userUUID) {
                        planName = plan.name
                    }
                }

                // 3) Build a new LoggedInState with code, userId, planName
                let newState = LoggedInState(
                    code: codeRecord.id,
                    userId: codeRecord.userId,
                    planName: planName
                )

                // 4) Encode into Data, store in @AppStorage
                let encoded = try JSONEncoder().encode(newState)
                loggedInStateData = encoded

            } catch {
                print(error)
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
            errorMessage = "Code not found, or invalid. Try again, checking the code from WatchClips website."
        }
    }
}
