/// Represents known plan names in the system.
enum PlanName: String, Codable, CaseIterable {
    case free  = "Free"
    case pro   = "Pro"
    
    // In case you want to expand to more plans in the future:
    // case premium = "Premium"
    // case deluxe  = "Deluxe"
    
    // MARK: - Helpers
    
    /// Human-readable display name (if you want
    /// a separate representation from the rawValue)
    var displayName: String {
        switch self {
        case .free:
            return "Free"
        case .pro:
            return "Pro"
        }
    }
}
