import Foundation

enum NodeShapePreference: String, CaseIterable, Identifiable, Sendable {
    case semantic
    case rounded
    case capsule
    case compact
    case ellipse
    case circle
    case diamond

    var id: Self { self }

    var displayName: String {
        switch self {
        case .semantic: "Distinct"
        case .rounded: "Rounded"
        case .capsule: "Capsule"
        case .compact: "Compact"
        case .ellipse: "Ellipse"
        case .circle: "Circle"
        case .diamond: "Diamond"
        }
    }

    var description: String {
        switch self {
        case .semantic: "Different silhouettes reinforce each kind."
        case .rounded: "A calm, consistent rounded rectangle."
        case .capsule: "A softer pill-shaped visual language."
        case .compact: "Tighter cards with restrained corners."
        case .ellipse: "Smooth elliptical thoughts."
        case .circle: "Equal circular forms."
        case .diamond: "Angular diamond-shaped thoughts."
        }
    }
}
