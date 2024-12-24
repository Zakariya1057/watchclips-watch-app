import SwiftUI
import Supabase

struct CodeItem: Decodable, Identifiable {
    let id: String
    let ipAddress: String?
    let expiresAt: Date?
    let lastAccessedAt: Date
    let accessCount: Int
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case ipAddress = "ip_address"
        case expiresAt = "expires_at"
        case lastAccessedAt = "last_accessed_at"
        case accessCount = "access_count"
        case createdAt = "created_at"
    }
}

struct CodesService {
    let client: SupabaseClient
    
    func fetchCode(byId id: String) async throws -> CodeItem {
        try await client
            .from("codes")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }
}

struct LoginView: View {
    @State private var code = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @AppStorage("loggedInCode") private var loggedInCode: String = ""
    
    private var codesService: CodesService {
        CodesService(client: supabase)
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
                    .ignoresSafeArea() // Covers the entire screen
                    
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
            Button("Close", role: .cancel) {
                // Just close the alert
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    func signInButtonTapped() {
        Task {
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }

            do {
                let codeRecord = try await codesService.fetchCode(byId: code)
                print("Code found: \(codeRecord.id)")
                loggedInCode = code
            } catch {
                // Attempt to handle known errors first
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
                    // If it's not a URLError, handle it as a generic error
                    errorMessage = "Code not found, try again by looking at the code on the WatchClips website."
                }
            }
        }
    }
}
