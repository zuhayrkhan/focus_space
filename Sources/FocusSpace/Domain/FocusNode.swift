import Foundation

struct FocusNode: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var position: SpatialPoint
    private(set) var attention: Double
    var parentID: UUID?
    var relatedNodeIDs: Set<UUID>
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        position: SpatialPoint = .zero,
        attention: Double = 0.5,
        parentID: UUID? = nil,
        relatedNodeIDs: Set<UUID> = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.position = position
        self.attention = Self.clamp(attention)
        self.parentID = parentID
        self.relatedNodeIDs = relatedNodeIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    mutating func setAttention(_ value: Double) {
        attention = Self.clamp(value)
        updatedAt = .now
    }

    mutating func move(to point: SpatialPoint) {
        position = point
        updatedAt = .now
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
