import Foundation

// MARK: - Time Filter

enum TimeFilter: CaseIterable, Identifiable, Hashable {
    case last7Days
    case last30Days
    case last90Days
    case custom(start: Date, end: Date)
    
    var id: String {
        switch self {
        case .last7Days: return "7days"
        case .last30Days: return "30days"
        case .last90Days: return "90days"
        case .custom: return "custom"
        }
    }
    
    var displayName: String {
        switch self {
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        case .last90Days: return "Last 90 Days"
        case .custom: return "Custom Range"
        }
    }
    
    func startDate(relativeTo date: Date = Date()) -> Date {
        switch self {
        case .last7Days:
            return Calendar.current.date(byAdding: .day, value: -7, to: date) ?? date
        case .last30Days:
            return Calendar.current.date(byAdding: .day, value: -30, to: date) ?? date
        case .last90Days:
            return Calendar.current.date(byAdding: .day, value: -90, to: date) ?? date
        case .custom(let start, _):
            return start
        }
    }
    
    func endDate(relativeTo date: Date = Date()) -> Date {
        switch self {
        case .last7Days, .last30Days, .last90Days:
            return date
        case .custom(_, let end):
            return end
        }
    }
    
    static var allCases: [TimeFilter] {
        [.last7Days, .last30Days, .last90Days]
    }
    
    static func == (lhs: TimeFilter, rhs: TimeFilter) -> Bool {
        switch (lhs, rhs) {
        case (.last7Days, .last7Days),
             (.last30Days, .last30Days),
             (.last90Days, .last90Days):
            return true
        case (.custom(let lhsStart, let lhsEnd), .custom(let rhsStart, let rhsEnd)):
            return lhsStart == rhsStart && lhsEnd == rhsEnd
        default:
            return false
        }
    }
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .last7Days:
            hasher.combine(0)
        case .last30Days:
            hasher.combine(1)
        case .last90Days:
            hasher.combine(2)
        case .custom(let start, let end):
            hasher.combine(3)
            hasher.combine(start.timeIntervalSince1970)
            hasher.combine(end.timeIntervalSince1970)
        }
    }
}

// MARK: - Region Filter

enum RegionFilter: Hashable, CaseIterable, Identifiable {
    case global
    case region(code: String, name: String)
    
    var id: String {
        switch self {
        case .global: return "global"
        case .region(let code, _): return code
        }
    }
    
    var displayName: String {
        switch self {
        case .global: return "Global"
        case .region(_, let name): return name
        }
    }
    
    var regionCode: String? {
        switch self {
        case .global: return nil
        case .region(let code, _): return code
        }
    }
    
    static var allCases: [RegionFilter] {
        [
            .global,
            .region(code: "US", name: "United States"),
            .region(code: "NG", name: "Nigeria"),
            .region(code: "GB", name: "United Kingdom"),
            .region(code: "CA", name: "Canada"),
            .region(code: "AU", name: "Australia"),
            .region(code: "DE", name: "Germany"),
            .region(code: "FR", name: "France"),
            .region(code: "BR", name: "Brazil"),
            .region(code: "IN", name: "India"),
            .region(code: "JP", name: "Japan")
        ]
    }
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .global:
            hasher.combine(0)
        case .region(let code, _):
            hasher.combine(1)
            hasher.combine(code)
        }
    }
}

// MARK: - Artist Summary

struct ArtistSummary: Decodable {
    let id: String
    let name: String
    let imageURL: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "artist_id"
        case name = "artist_name"
        case imageURL = "artist_image_url"
    }
}

