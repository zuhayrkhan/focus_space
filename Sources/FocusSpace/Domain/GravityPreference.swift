import Foundation

enum GravityPreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case inherit
    case enabled
    case disabled

    var id: Self { self }

    var displayName: String {
        switch self {
        case .inherit: "Use workspace setting"
        case .enabled: "Always on"
        case .disabled: "Off for this thought"
        }
    }
}
