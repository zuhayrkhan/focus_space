import Foundation

struct FocusSceneSnapshot: Equatable, Sendable {
    struct Item: Identifiable, Equatable, Sendable {
        let id: UUID
        let title: String
        let kind: FocusNodeKind
        let position: SpatialPoint
        let attention: Double
        let parentID: UUID?
        let hierarchyDepth: Int
        let urgency: FocusNodeUrgency
        let isEnabled: Bool
        let isSelected: Bool
        let isDimmed: Bool
    }

    let items: [Item]
}
