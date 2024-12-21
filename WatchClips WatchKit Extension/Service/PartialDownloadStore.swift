import Foundation

struct PartialRecord: Codable, Equatable {
    let remoteURL: String
    var offset: Int64
    var totalSize: Int64
}

/// Simple store to persist partial offsets in UserDefaults.
class PartialDownloadStore {
    private let userDefaultsKey = "PartialDownloads"

    func loadRecords() -> [PartialRecord] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([PartialRecord].self, from: data)
        } catch {
            print("Failed to decode partial records: \(error)")
            return []
        }
    }

    func saveRecords(_ records: [PartialRecord]) {
        do {
            let data = try JSONEncoder().encode(records)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("Failed to encode partial records: \(error)")
        }
    }
}
