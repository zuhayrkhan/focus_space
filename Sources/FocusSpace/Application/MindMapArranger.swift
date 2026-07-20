import Foundation

struct MindMapArranger {
    private static let horizontalSpacing = 2.05
    private static let verticalSpacing = 0.94
    private static let branchGap = 0.34

    static func positions(for map: FocusMap) -> [UUID: SpatialPoint] {
        guard !map.nodes.isEmpty else { return [:] }
        let ids = Set(map.nodes.map(\.id))
        let nodeByID = Dictionary(uniqueKeysWithValues: map.nodes.map { ($0.id, $0) })
        let children = Dictionary(grouping: map.nodes.filter { $0.parentID != nil }) { $0.parentID! }
            .mapValues(sortedNodes)
        let roots = sortedNodes(map.nodes.filter { $0.parentID == nil || !ids.contains($0.parentID!) })

        if roots.count > 8, roots.allSatisfy({ children[$0.id, default: []].isEmpty }) {
            return gridPositions(for: roots)
        }

        var arranged: Set<UUID> = []
        var islands: [[UUID: SpatialPoint]] = []
        for candidate in roots + sortedNodes(map.nodes) where !arranged.contains(candidate.id) {
            let island = treePositions(
                rootID: candidate.id,
                nodeByID: nodeByID,
                children: children,
                excluding: arranged
            )
            guard !island.isEmpty else { continue }
            arranged.formUnion(island.keys)
            islands.append(island)
        }
        return pack(islands: islands)
    }

    static func positionForNewChild(in map: FocusMap, parentID: UUID?) -> SpatialPoint {
        guard let parentID, let parent = map.node(id: parentID) else {
            guard !map.nodes.isEmpty else { return .zero }
            let maxX = map.nodes.map(\.position.x).max() ?? 0
            let minY = map.nodes.map(\.position.y).min() ?? 0
            let maxY = map.nodes.map(\.position.y).max() ?? 0
            return SpatialPoint(x: maxX + horizontalSpacing * 1.7, y: (minY + maxY) / 2)
        }

        let root = map.ancestors(of: parent.id).last.flatMap(map.node(id:)) ?? parent
        let directChildren = map.nodes.filter { $0.parentID == parent.id }
        let side: Double
        if root.id == parent.id {
            let leftCount = directChildren.count { $0.position.x < parent.position.x }
            let rightCount = directChildren.count { $0.position.x > parent.position.x }
            side = rightCount <= leftCount ? 1 : -1
        } else {
            let rootDelta = parent.position.x - root.position.x
            if abs(rootDelta) > 0.05 {
                side = rootDelta > 0 ? 1 : -1
            } else if let immediateParent = parent.parentID.flatMap(map.node(id:)) {
                side = parent.position.x >= immediateParent.position.x ? 1 : -1
            } else {
                side = 1
            }
        }

        let siblingsOnSide = directChildren.filter {
            side * ($0.position.x - parent.position.x) > 0
        }.count
        return SpatialPoint(
            x: parent.position.x + side * horizontalSpacing,
            y: parent.position.y + staggeredOffset(for: siblingsOnSide)
        )
    }

    private static func treePositions(
        rootID: UUID,
        nodeByID: [UUID: FocusNode],
        children: [UUID: [FocusNode]],
        excluding: Set<UUID>
    ) -> [UUID: SpatialPoint] {
        guard nodeByID[rootID] != nil, !excluding.contains(rootID) else { return [:] }
        var positions: [UUID: SpatialPoint] = [rootID: .zero]
        let directChildren = children[rootID, default: []].filter { !excluding.contains($0.id) }
        var left: [(node: FocusNode, weight: Int)] = []
        var right: [(node: FocusNode, weight: Int)] = []
        var leftWeight = 0
        var rightWeight = 0

        let weighted = directChildren.map { node in
            (
                node: node,
                weight: subtreeWeight(
                    of: node.id,
                    children: children,
                    excluding: excluding,
                    ancestry: [rootID]
                )
            )
        }.sorted {
            if $0.weight != $1.weight { return $0.weight > $1.weight }
            return nodeComesBefore($0.node, $1.node)
        }
        for branch in weighted {
            if rightWeight <= leftWeight {
                right.append(branch)
                rightWeight += branch.weight
            } else {
                left.append(branch)
                leftWeight += branch.weight
            }
        }

        placeSide(
            sortedBranches(left), side: -1, rootID: rootID,
            nodeByID: nodeByID, children: children, excluding: excluding,
            positions: &positions
        )
        placeSide(
            sortedBranches(right), side: 1, rootID: rootID,
            nodeByID: nodeByID, children: children, excluding: excluding,
            positions: &positions
        )
        return positions
    }

    private static func placeSide(
        _ branches: [(node: FocusNode, weight: Int)],
        side: Double,
        rootID: UUID,
        nodeByID: [UUID: FocusNode],
        children: [UUID: [FocusNode]],
        excluding: Set<UUID>,
        positions: inout [UUID: SpatialPoint]
    ) {
        guard !branches.isEmpty else { return }
        var sidePositions: [UUID: SpatialPoint] = [:]
        var cursor = 0.0

        func place(_ id: UUID, depth: Int, ancestry: Set<UUID>) -> Double {
            guard !ancestry.contains(id), !excluding.contains(id), nodeByID[id] != nil else {
                let y = cursor
                cursor -= verticalSpacing
                return y
            }
            let descendants = children[id, default: []].filter {
                !ancestry.contains($0.id) && !excluding.contains($0.id)
            }
            let y: Double
            if descendants.isEmpty {
                y = cursor
                cursor -= verticalSpacing
            } else {
                let childYs = descendants.map {
                    place($0.id, depth: depth + 1, ancestry: ancestry.union([id]))
                }
                y = ((childYs.first ?? cursor) + (childYs.last ?? cursor)) / 2
            }
            sidePositions[id] = SpatialPoint(x: side * Double(depth) * horizontalSpacing, y: y)
            return y
        }

        for branch in branches {
            _ = place(branch.node.id, depth: 1, ancestry: [rootID])
            cursor -= branchGap
        }
        let ys = sidePositions.values.map(\.y)
        let centreY = ((ys.min() ?? 0) + (ys.max() ?? 0)) / 2
        positions.merge(
            sidePositions.mapValues { SpatialPoint(x: $0.x, y: $0.y - centreY) },
            uniquingKeysWith: { current, _ in current }
        )
    }

    private static func subtreeWeight(
        of id: UUID,
        children: [UUID: [FocusNode]],
        excluding: Set<UUID>,
        ancestry: Set<UUID>
    ) -> Int {
        guard !ancestry.contains(id), !excluding.contains(id) else { return 1 }
        let descendants = children[id, default: []].filter {
            !ancestry.contains($0.id) && !excluding.contains($0.id)
        }
        guard !descendants.isEmpty else { return 1 }
        return descendants.reduce(0) {
            $0 + subtreeWeight(
                of: $1.id,
                children: children,
                excluding: excluding,
                ancestry: ancestry.union([id])
            )
        }
    }

    private static func pack(islands: [[UUID: SpatialPoint]]) -> [UUID: SpatialPoint] {
        guard islands.count > 1 else { return islands.first ?? [:] }
        let maximumWidth = islands.map { bounds(of: $0).width }.max() ?? 0
        let maximumHeight = islands.map { bounds(of: $0).height }.max() ?? 0
        let columns = min(2, max(1, Int(ceil(sqrt(Double(islands.count))))))
        let rows = Int(ceil(Double(islands.count) / Double(columns)))
        let cellWidth = maximumWidth + horizontalSpacing * 1.7
        let cellHeight = maximumHeight + verticalSpacing * 2.8
        let totalHeight = Double(rows - 1) * cellHeight
        var result: [UUID: SpatialPoint] = [:]

        for (index, island) in islands.enumerated() {
            let column = index % columns
            let row = index / columns
            let itemsInRow = min(columns, islands.count - row * columns)
            let rowWidth = Double(itemsInRow - 1) * cellWidth
            let offset = SpatialPoint(
                x: Double(column) * cellWidth - rowWidth / 2,
                y: totalHeight / 2 - Double(row) * cellHeight
            )
            for (id, point) in island {
                result[id] = SpatialPoint(x: point.x + offset.x, y: point.y + offset.y)
            }
        }
        return result
    }

    private static func bounds(of positions: [UUID: SpatialPoint]) -> (width: Double, height: Double) {
        let xs = positions.values.map(\.x)
        let ys = positions.values.map(\.y)
        return ((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0))
    }

    private static func sortedBranches(
        _ branches: [(node: FocusNode, weight: Int)]
    ) -> [(node: FocusNode, weight: Int)] {
        branches.sorted { nodeComesBefore($0.node, $1.node) }
    }

    private static func sortedNodes(_ nodes: [FocusNode]) -> [FocusNode] {
        nodes.sorted(by: nodeComesBefore)
    }

    private static func nodeComesBefore(_ lhs: FocusNode, _ rhs: FocusNode) -> Bool {
        if lhs.position.y != rhs.position.y { return lhs.position.y > rhs.position.y }
        if lhs.position.x != rhs.position.x { return lhs.position.x < rhs.position.x }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private static func staggeredOffset(for index: Int) -> Double {
        guard index > 0 else { return 0 }
        let magnitude = Double((index + 1) / 2) * verticalSpacing
        return index.isMultiple(of: 2) ? -magnitude : magnitude
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
