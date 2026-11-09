import Foundation

enum TVApp: String, CaseIterable, Identifiable {
    case netflix = "Netflix", youtube = "YouTube", appleTV = "Apple TV"
    var id: String { rawValue }

    func installedID(in apps: [[String: Any]]) -> String? {
        let knownID: String
        switch self {
        case .netflix: knownID = "netflix"
        case .youtube: knownID = "youtube.leanback.v4"
        case .appleTV: knownID = "com.apple.appletv"
        }
        if apps.contains(where: { $0["id"] as? String == knownID }) { return knownID }
        return apps.first {
            guard let title = $0["title"] as? String, let id = $0["id"] as? String, !id.isEmpty else { return false }
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return name == rawValue.lowercased() || (self == .appleTV && name == "apple tv+")
        }?["id"] as? String
    }
}
