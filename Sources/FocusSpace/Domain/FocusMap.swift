import Foundation

struct FocusMap: Codable, Equatable, Sendable {
    static let currentVersion = 3

    private(set) var version = Self.currentVersion
    var title: String
    var nodes: [FocusNode]

    init(title: String = "My Focus Space", nodes: [FocusNode] = []) {
        self.title = title
        self.nodes = nodes
    }

    private enum CodingKeys: String, CodingKey {
        case version, title, nodes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decodeIfPresent(Int.self, forKey: .version)
        version = Self.currentVersion
        title = try container.decode(String.self, forKey: .title)
        nodes = try container.decode([FocusNode].self, forKey: .nodes)
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
}
