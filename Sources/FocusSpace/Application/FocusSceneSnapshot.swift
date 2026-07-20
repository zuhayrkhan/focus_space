import Foundation

struct FocusSceneSnapshot: Equatable, Sendable {
    enum ContextRole: Equatable, Sendable {
        case none
        case subdued
        case branch
        case direct
    }

    struct Item: Identifiable, Equatable, Sendable {
        let id: UUID
        let title: String
        let notes: String
        let kind: FocusNodeKind
        let position: SpatialPoint
        let attention: Double
        let manualAttention: Double
        let gravityReason: String?
        let isGravityInfluenced: Bool
        let parentID: UUID?
        let hierarchyDepth: Int
        let urgency: FocusNodeUrgency
        let isEnabled: Bool
        let isSelected: Bool
        let isDimmed: Bool
        let isHovered: Bool
        let contextRole: ContextRole

        init(
            id: UUID,
            title: String,
            notes: String = "",
            kind: FocusNodeKind,
            position: SpatialPoint,
            attention: Double,
            manualAttention: Double? = nil,
            gravityReason: String? = nil,
            isGravityInfluenced: Bool = false,
            parentID: UUID?,
            hierarchyDepth: Int,
            urgency: FocusNodeUrgency,
            isEnabled: Bool,
            isSelected: Bool,
            isDimmed: Bool,
            isHovered: Bool = false,
            contextRole: ContextRole = .none
        ) {
            self.id = id
            self.title = title
            self.notes = notes
            self.kind = kind
            self.position = position
            self.attention = attention
            self.manualAttention = manualAttention ?? attention
            self.gravityReason = gravityReason
            self.isGravityInfluenced = isGravityInfluenced
            self.parentID = parentID
            self.hierarchyDepth = hierarchyDepth
            self.urgency = urgency
            self.isEnabled = isEnabled
            self.isSelected = isSelected
            self.isDimmed = isDimmed
            self.isHovered = isHovered
            self.contextRole = contextRole
        }
    }

    struct Relationship: Identifiable, Equatable, Sendable {
        enum Kind: String, Equatable, Sendable {
            case hierarchy
            case crossLink
        }

        enum Emphasis: Int, Comparable, Equatable, Sendable {
            case subdued
            case standard
            case branch
            case direct

            static func < (lhs: Self, rhs: Self) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }

        struct ID: Hashable, Sendable {
            let kind: Kind
            let sourceID: UUID
            let targetID: UUID
        }

        let id: ID
        let sourceID: UUID
        let targetID: UUID
        let kind: Kind
        let emphasis: Emphasis
        let attention: Double
        let isDimmed: Bool
    }

    let items: [Item]
    let relationships: [Relationship]

    init(items: [Item], relationships: [Relationship] = []) {
        self.items = items
        self.relationships = relationships
    }
}
