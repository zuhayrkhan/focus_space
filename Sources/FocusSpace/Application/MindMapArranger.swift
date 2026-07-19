import Foundation

struct MindMapArranger {
    static func positions(for map: FocusMap) -> [UUID: SpatialPoint] {
        guard !map.nodes.isEmpty else { return [:] }
        let ids = Set(map.nodes.map(\.id))
        let nodeByID = Dictionary(uniqueKeysWithValues: map.nodes.map { ($0.id, $0) })
        let children = Dictionary(grouping: map.nodes.filter { $0.parentID != nil }) { $0.parentID! }
            .mapValues { nodes in
                nodes.sorted { lhs, rhs in
                    lhs.position.x == rhs.position.x
                        ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                        : lhs.position.x < rhs.position.x
                }
            }
        let roots = map.nodes
            .filter { $0.parentID == nil || !ids.contains($0.parentID!) }
            .sorted { $0.position.x < $1.position.x }

        if roots.count > 8, roots.allSatisfy({ children[$0.id, default: []].isEmpty }) {
            return gridPositions(for: roots)
        }

        var positions: [UUID: SpatialPoint] = [:]
        var visited: Set<UUID> = []
        var leafCursor = 0.0
        let horizontalSpacing = 1.72
        let verticalSpacing = 1.08

        func place(_ id: UUID, depth: Int, ancestry: Set<UUID>) -> Double {
            guard !ancestry.contains(id), let node = nodeByID[id] else {
                let x = leafCursor
                leafCursor += horizontalSpacing
                return x
            }
            visited.insert(id)
            let descendants = children[id, default: []].filter { !ancestry.contains($0.id) }
            let x: Double
            if descendants.isEmpty {
                x = leafCursor
                leafCursor += horizontalSpacing
            } else {
                let childXs = descendants.map {
                    place($0.id, depth: depth + 1, ancestry: ancestry.union([id]))
                }
                x = ((childXs.first ?? leafCursor) + (childXs.last ?? leafCursor)) / 2
            }
            positions[node.id] = SpatialPoint(x: x, y: 1.45 - Double(depth) * verticalSpacing)
            return x
        }

        for root in roots { _ = place(root.id, depth: 0, ancestry: []) }
        for node in map.nodes where !visited.contains(node.id) {
            _ = place(node.id, depth: 0, ancestry: [])
        }

        let xs = positions.values.map(\.x)
        let centre = ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2
        return positions.mapValues { SpatialPoint(x: $0.x - centre, y: $0.y) }
    }

    private static func gridPositions(for nodes: [FocusNode]) -> [UUID: SpatialPoint] {
        let columns = min(6, max(1, Int(ceil(sqrt(Double(nodes.count))))))
        let horizontalSpacing = 1.72
        let verticalSpacing = 0.96
        return Dictionary(uniqueKeysWithValues: nodes.enumerated().map { index, node in
            let column = index % columns
            let row = index / columns
            let rowCount = min(columns, nodes.count - row * columns)
            let rowWidth = Double(rowCount - 1) * horizontalSpacing
            return (
                node.id,
                SpatialPoint(
                    x: Double(column) * horizontalSpacing - rowWidth / 2,
                    y: 1.3 - Double(row) * verticalSpacing
                )
            )
        })
    }
}
