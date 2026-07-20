import Foundation

enum AttentionBand: String, CaseIterable, Codable, Identifiable, Sendable {
    case now
    case thisWeek
    case thisSprint
    case thisQuarter
    case someday

    var id: Self { self }

    var displayName: String {
        switch self {
        case .now: "Now"
        case .thisWeek: "This week"
        case .thisSprint: "This sprint"
        case .thisQuarter: "This quarter"
        case .someday: "Someday"
        }
    }

    var attention: Double {
        switch self {
        case .now: 0.94
        case .thisWeek: 0.74
        case .thisSprint: 0.55
        case .thisQuarter: 0.33
        case .someday: 0.10
        }
    }

    static func nearest(to attention: Double) -> Self {
        allCases.min { abs($0.attention - attention) < abs($1.attention - attention) } ?? .thisSprint
    }
}
