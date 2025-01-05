import Foundation

/// This struct maps to your `plans` table row.
struct Plan: Equatable, Identifiable, Codable {
    let id: Int
    let name: PlanName
    let monthlyPriceCents: Int
    let maxVideoCount: Int
    let features: PlanFeatures? // Your typed features struct
    
    let createdAt: Date?
    let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case monthlyPriceCents = "monthly_price_cents"
        case maxVideoCount     = "max_video_count"
        case features
        case createdAt         = "created_at"
        case updatedAt         = "updated_at"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // 1) Decode basic fields
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(PlanName.self, forKey: .name)
        monthlyPriceCents = try container.decode(Int.self, forKey: .monthlyPriceCents)
        maxVideoCount = try container.decode(Int.self, forKey: .maxVideoCount)
        
        // 2) Decode `features` as a `PlanFeatures` struct (optional)
        features = try? container.decode(PlanFeatures.self, forKey: .features)
        
        // 3) Decode `createdAt` and `updatedAt` with flexible date parsing
        createdAt = try Self.decodeFlexibleDate(container: container, key: .createdAt)
        updatedAt = try Self.decodeFlexibleDate(container: container, key: .updatedAt)
    }
    
    /// Helper to decode a Date from either a numeric timestamp or an ISO string.
    private static func decodeFlexibleDate(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> Date? {
        
        // Try decoding as a Unix timestamp
        if let seconds = try? container.decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: seconds)
        }
        
        // Try decoding as a string (ISO8601 or a custom format)
        if let dateString = try? container.decode(String.self, forKey: key) {
            // Attempt ISO8601
            let isoFormatter = ISO8601DateFormatter()
            if let date = isoFormatter.date(from: dateString) {
                return date
            }
            // If your backend uses another format:
            let customFormatter = DateFormatter()
            customFormatter.dateFormat = "yyyy-MM-dd HH:mm:ssZ"  // Example
            if let date = customFormatter.date(from: dateString) {
                return date
            }
            // If all fail, return nil
            return nil
        }
        
        // If neither approach works, return nil
        return nil
    }
}
