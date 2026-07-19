import Foundation

enum NodeShapePreference: String, CaseIterable, Identifiable, Sendable {
    case semantic
    case rounded
    case capsule
    case compact

    var id: Self { self }

    var displayName: String {
        switch self {
        case .semantic: "Distinct"
        case .rounded: "Rounded"
        case .capsule: "Capsule"
        case .compact: "Compact"
        }
    }

    var description: String {
        switch self {
        case .semantic: "Different silhouettes reinforce each kind."
        case .rounded: "A calm, consistent rounded rectangle."
        case .capsule: "A softer pill-shaped visual language."
        case .compact: "Tighter cards with restrained corners."
        }
    }
}
