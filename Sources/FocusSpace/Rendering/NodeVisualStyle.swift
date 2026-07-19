import Foundation

enum NodeSilhouette: Equatable, Sendable {
    case panel
    case capsule
    case compact
    case note
    case ghost
}

struct NodeVisualStyle: Equatable, Sendable {
    let silhouette: NodeSilhouette
    let width: Float
    let height: Float
    let cornerRadius: Float
    let color: VisualColor
    let glyph: String
    let opacity: Float
    let saturation: Float
    let emissiveIntensity: Float
    let borderOpacity: Float
    let hierarchyOffset: Float
    let urgencyGlyph: String?
    let urgencyColor: VisualColor?

    static func resolve(
        kind: FocusNodeKind,
        attention: Double,
        hierarchyDepth: Int,
        urgency: FocusNodeUrgency,
        isEnabled: Bool
    ) -> Self {
        let attention = Float(min(max(attention, 0), 1))
        let family: (
            NodeSilhouette,
            Float,
            Float,
            Float,
            VisualColor,
            String
        ) = switch kind {
        case .project:
            (.panel, 1.58, 0.68, 0.13, VisualColor(0.10, 0.35, 0.72), "◆")
        case .group:
            (.capsule, 1.42, 0.58, 0.25, VisualColor(0.34, 0.19, 0.68), "◇")
        case .task:
            (.compact, 1.30, 0.52, 0.11, VisualColor(0.10, 0.43, 0.27), "✓")
        case .reference:
            (.note, 1.36, 0.56, 0.045, VisualColor(0.55, 0.36, 0.08), "▤")
        case .someday:
            (.ghost, 1.34, 0.52, 0.24, VisualColor(0.28, 0.35, 0.40), "○")
        }

        let urgencyVisual: (String?, VisualColor?) = switch urgency {
        case .none: (nil, nil)
        case .soon: ("!", VisualColor(1.0, 0.66, 0.12))
        case .overdue: ("!", VisualColor(1.0, 0.24, 0.18))
        }
        let enabledMultiplier: Float = isEnabled ? 1 : 0.42
        return Self(
            silhouette: family.0,
            width: family.1,
            height: family.2,
            cornerRadius: family.3,
            color: family.4,
            glyph: isEnabled ? family.5 : "—",
            opacity: enabledMultiplier * (0.45 + attention * 0.55),
            saturation: (isEnabled ? 0.48 : 0.08) + attention * (isEnabled ? 0.52 : 0.12),
            emissiveIntensity: isEnabled ? 0.045 + attention * 0.22 : 0.015,
            borderOpacity: enabledMultiplier * (0.26 + attention * 0.64),
            hierarchyOffset: -Float(hierarchyDepth) * 0.045 + (kind == .project ? 0.10 : 0),
            urgencyGlyph: urgencyVisual.0,
            urgencyColor: urgencyVisual.1
        )
    }
}

enum NodeLabelLayout {
    static func displayTitle(
        _ title: String,
        maximumCharacters: Int = 38,
        singleLineLimit: Int = 15
    ) -> String {
        let normalized = title
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !normalized.isEmpty else { return "Untitled" }

        var characters = Array(normalized)
        if characters.count > maximumCharacters {
            characters = Array(characters.prefix(maximumCharacters - 1)) + ["…"]
        }
        let concise = String(characters)
        guard characters.count > singleLineLimit else { return concise }

        let midpoint = characters.count / 2
        let spaces = characters.indices.filter {
            characters[$0].isWhitespace
                && $0 >= 4
                && characters.count - $0 - 1 >= 4
        }
        if let split = spaces.min(by: { abs($0 - midpoint) < abs($1 - midpoint) }),
           split >= 4,
           characters.count - split - 1 >= 4 {
            return String(characters[..<split]) + "\n" + String(characters[(split + 1)...])
        }

        let split = min(max(midpoint, 8), characters.count - 6)
        return String(characters[..<split]) + "\n" + String(characters[split...])
    }
}
