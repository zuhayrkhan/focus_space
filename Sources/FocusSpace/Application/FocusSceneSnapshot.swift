import Foundation

struct FocusSceneSnapshot: Equatable, Sendable {
    struct Item: Identifiable, Equatable, Sendable {
        let id: UUID
        let title: String
        let position: SpatialPoint
        let attention: Double
        let parentID: UUID?
        let isSelected: Bool
        let isDimmed: Bool
    }

    let items: [Item]
}
