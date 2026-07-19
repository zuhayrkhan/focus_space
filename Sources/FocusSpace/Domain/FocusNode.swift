import Foundation

enum FocusNodeKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case project
    case group
    case task
    case reference
    case someday

    var id: Self { self }

    var displayName: String {
        switch self {
        case .project: "Project / Area"
        case .group: "Group / Subcategory"
        case .task: "Task / Item"
        case .reference: "Reference / Note"
        case .someday: "Someday / Maybe"
        }
    }
}

enum FocusNodeUrgency: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case soon
    case overdue

    var id: Self { self }

    var displayName: String {
        switch self {
        case .none: "No urgency"
        case .soon: "Due soon"
        case .overdue: "Overdue"
        }
    }
}

struct FocusNode: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var kind: FocusNodeKind
    var position: SpatialPoint
    private(set) var attention: Double
    var parentID: UUID?
    var relatedNodeIDs: Set<UUID>
    var urgency: FocusNodeUrgency
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        kind: FocusNodeKind = .task,
        position: SpatialPoint = .zero,
        attention: Double = 0.5,
        parentID: UUID? = nil,
        relatedNodeIDs: Set<UUID> = [],
        urgency: FocusNodeUrgency = .none,
        isEnabled: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.position = position
        self.attention = Self.clamp(attention)
        self.parentID = parentID
        self.relatedNodeIDs = relatedNodeIDs
        self.urgency = urgency
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, kind, position, attention, parentID, relatedNodeIDs
        case urgency, isEnabled, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decodeIfPresent(FocusNodeKind.self, forKey: .kind) ?? .task
        position = try container.decode(SpatialPoint.self, forKey: .position)
        attention = Self.clamp(try container.decode(Double.self, forKey: .attention))
        parentID = try container.decodeIfPresent(UUID.self, forKey: .parentID)
        relatedNodeIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .relatedNodeIDs) ?? []
        urgency = try container.decodeIfPresent(FocusNodeUrgency.self, forKey: .urgency) ?? .none
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
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
