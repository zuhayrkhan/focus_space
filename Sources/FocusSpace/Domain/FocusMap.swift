import Foundation

struct FocusMap: Codable, Equatable, Sendable {
    static let currentVersion = 4

    private(set) var version = Self.currentVersion
    var title: String
    var nodes: [FocusNode]
    var isGravityEnabled: Bool

    init(title: String = "My Focus Space", nodes: [FocusNode] = [], isGravityEnabled: Bool = false) {
        self.title = title
        self.nodes = nodes
        self.isGravityEnabled = isGravityEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case version, title, nodes, isGravityEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard decodedVersion <= Self.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "This map uses newer schema version \(decodedVersion); this app supports through version \(Self.currentVersion)."
            )
        }
        version = Self.currentVersion
        title = try container.decode(String.self, forKey: .title)
        nodes = try container.decode([FocusNode].self, forKey: .nodes)
        isGravityEnabled = try container.decodeIfPresent(Bool.self, forKey: .isGravityEnabled) ?? false
    }

    func node(id: UUID) -> FocusNode? {
        nodes.first { $0.id == id }
    }

    mutating func updateNode(id: UUID, _ change: (inout FocusNode) -> Void) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        change(&nodes[index])
    }

    mutating func removeNodeAndDescendants(id: UUID) {
        let descendantIDs = descendants(of: id).union([id])
        nodes.removeAll { descendantIDs.contains($0.id) }
        for index in nodes.indices {
            nodes[index].relatedNodeIDs.subtract(descendantIDs)
        }
    }

    func descendants(of id: UUID) -> Set<UUID> {
        var result = Set<UUID>()
        var frontier = [id]
        while let parent = frontier.popLast() {
            let children = nodes.filter { $0.parentID == parent }.map(\.id)
            for child in children where result.insert(child).inserted {
                frontier.append(child)
            }
        }
        return result
    }

    func ancestors(of id: UUID) -> [UUID] {
        var result: [UUID] = []
        var visited: Set<UUID> = [id]
        var parentID = node(id: id)?.parentID
        while let currentID = parentID,
              visited.insert(currentID).inserted,
              let parent = node(id: currentID) {
            result.append(currentID)
            parentID = parent.parentID
        }
        return result
    }

    func connectedComponent(containing id: UUID) -> Set<UUID> {
        guard node(id: id) != nil else { return [] }
        var adjacency: [UUID: Set<UUID>] = [:]
        let validIDs = Set(nodes.map(\.id))

        for node in nodes {
            if let parentID = node.parentID, validIDs.contains(parentID) {
                adjacency[node.id, default: []].insert(parentID)
                adjacency[parentID, default: []].insert(node.id)
            }
            for relatedID in node.relatedNodeIDs where validIDs.contains(relatedID) {
                adjacency[node.id, default: []].insert(relatedID)
                adjacency[relatedID, default: []].insert(node.id)
            }
        }

        var result: Set<UUID> = [id]
        var frontier = [id]
        while let current = frontier.popLast() {
            for neighbour in adjacency[current, default: []] where result.insert(neighbour).inserted {
                frontier.append(neighbour)
            }
        }
        return result
    }
}
