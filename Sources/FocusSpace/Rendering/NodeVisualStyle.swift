import Foundation

enum NodeSilhouette: Equatable, Sendable {
    case panel
    case capsule
    case compact
    case note
    case ghost
    case ellipse
    case circle
    case diamond
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
        isEnabled: Bool,
        shapePreference: NodeShapePreference = .semantic,
        isExpanded: Bool = false,
        colorVariation: Double = 0.5
    ) -> Self {
        let attention = Float(min(max(attention, 0), 1))
        let family: (
            NodeSilhouette,
            Float,
            Float,
            Float,
            VisualColor,
            VisualColor,
            String
        ) = switch kind {
        case .project:
            (.panel, 1.58, 0.68, 0.13, VisualColor(0.07, 0.28, 0.62), VisualColor(0.10, 0.50, 0.78), "◆")
        case .group:
            (.ellipse, 1.46, 0.68, 0, VisualColor(0.28, 0.14, 0.58), VisualColor(0.48, 0.24, 0.72), "◇")
        case .task:
            (.capsule, 1.34, 0.54, 0.24, VisualColor(0.07, 0.34, 0.20), VisualColor(0.12, 0.54, 0.36), "✓")
        case .reference:
            (.diamond, 1.48, 0.88, 0, VisualColor(0.48, 0.27, 0.05), VisualColor(0.68, 0.43, 0.10), "▤")
        case .someday:
            (.circle, 0.98, 0.98, 0, VisualColor(0.22, 0.29, 0.35), VisualColor(0.38, 0.44, 0.48), "○")
        }

        let preferredShape: (NodeSilhouette, Float, Float, Float) = switch shapePreference {
        case .semantic: (family.0, family.1, family.2, family.3)
        case .rounded: (.panel, 1.50, 0.60, 0.13)
        case .capsule: (.capsule, 1.50, 0.58, 0.26)
        case .compact: (.compact, 1.34, 0.52, 0.055)
        case .ellipse: (.ellipse, 1.52, 0.70, 0)
        case .circle: (.circle, 1.04, 1.04, 0)
        case .diamond: (.diamond, 1.50, 0.90, 0)
        }
        let expandedWidth = isExpanded ? max(preferredShape.1 + 0.24, 1.72) : preferredShape.1
        let expandedHeight = isExpanded ? preferredShape.2 + 0.72 : preferredShape.2
        let urgencyVisual: (String?, VisualColor?) = switch urgency {
        case .none: (nil, nil)
        case .soon: ("!", VisualColor(1.0, 0.66, 0.12))
        case .overdue: ("!", VisualColor(1.0, 0.24, 0.18))
        }
        let enabledMultiplier: Float = isEnabled ? 1 : 0.42
        return Self(
            silhouette: preferredShape.0,
            width: expandedWidth,
            height: expandedHeight,
            cornerRadius: preferredShape.3,
            color: family.4.interpolated(to: family.5, fraction: colorVariation),
            glyph: isEnabled ? family.6 : "—",
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

enum NodeNotesLayout {
    static func displayText(_ notes: String, maximumCharacters: Int = 150) -> String {
        let normalized = notes
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard normalized.count > maximumCharacters else { return normalized }
        return String(normalized.prefix(maximumCharacters - 1)) + "…"
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
