import Foundation
// MARK: - Data Models

/// Tracks partial offset for a given URL
struct PartialRecord: Codable, Equatable {
    let urlString: String
    var offset: Int64
    var totalSize: Int64
}

/// Simple store that uses UserDefaults to persist partial offsets across app launches
class PartialDownloadStore {
    private let userDefaultsKey = "PartialDownloads"
    
    func loadAllRecords() -> [PartialRecord] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([PartialRecord].self, from: data)
        } catch {
            print("[PartialDownloadStore] [ERROR] decode: \(error)")
            return []
        }
    }
    
    func saveAllRecords(_ records: [PartialRecord]) {
        do {
            let data = try JSONEncoder().encode(records)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("[PartialDownloadStore] [ERROR] encode: \(error)")
        }
    }
    
    func loadRecord(for url: URL) -> PartialRecord? {
        loadAllRecords().first(where: { $0.urlString == url.absoluteString })
    }
    
    func saveOrUpdateRecord(_ record: PartialRecord) {
        var all = loadAllRecords()
        if let idx = all.firstIndex(where: { $0.urlString == record.urlString }) {
            all[idx] = record
        } else {
            all.append(record)
        }
        saveAllRecords(all)
    }
    
    func removeRecord(for url: URL) {
        var all = loadAllRecords()
        all.removeAll(where: { $0.urlString == url.absoluteString })
        saveAllRecords(all)
    }
}
