import Foundation

enum WorkspacePresentationLevel: String, Equatable, Sendable {
    case atlas
    case branch
    case detail
}

enum NodePresentationLevel: String, Equatable, Sendable {
    case hidden
    case silhouette
    case miniature
    case reduced
    case compact
    case full
    case atlas

    var isSpatiallyVisible: Bool { self != .hidden }

    var scale: Float {
        switch self {
        case .hidden: 0
        case .silhouette: 0.50
        case .miniature: 0.59
        case .reduced: 0.70
        case .compact: 0.84
        case .full: 1
        case .atlas: 0.88
        }
    }

    var labelScale: CGFloat {
        switch self {
        case .hidden: 0
        case .silhouette: 0.78
        case .miniature: 0.84
        case .reduced: 0.90
        case .compact: 0.96
        case .full, .atlas: 1
        }
    }

    var labelOpacity: Double {
        switch self {
        case .hidden: 0
        case .silhouette: 0.36
        case .miniature: 0.54
        case .reduced: 0.72
        case .compact: 0.88
        case .full, .atlas: 1
        }
    }

    var maximumLabelCharacters: Int {
        switch self {
        case .hidden: 0
        case .silhouette: 14
        case .miniature: 18
        case .reduced: 24
        case .compact: 30
        case .full, .atlas: 38
        }
    }

    var showsKindGlyph: Bool {
        switch self {
        case .hidden, .silhouette, .miniature: false
        case .reduced, .compact, .full, .atlas: true
        }
    }

    var requiresExpandedHitTarget: Bool {
        switch self {
        case .silhouette, .miniature, .reduced, .compact: true
        case .hidden, .full, .atlas: false
        }
    }
}

struct FocusIslandSummary: Identifiable, Equatable, Sendable {
    let rootID: UUID
    let title: String
    let thoughtCount: Int
    let minimumAttention: Double
    let maximumAttention: Double
    let urgentCount: Int
    let nodeIDs: Set<UUID>

    var id: UUID { rootID }

    var detailText: String {
        let attention = "\(Int((minimumAttention * 100).rounded()))–\(Int((maximumAttention * 100).rounded()))% attention"
        let urgency = urgentCount == 0 ? "No urgent thoughts" : "\(urgentCount) urgent"
        return "\(thoughtCount) \(thoughtCount == 1 ? "thought" : "thoughts") · \(attention)\n\(urgency)"
    }
}

struct SpatialPresentation: Equatable, Sendable {
    struct NodeIntent: Equatable, Sendable {
        let level: NodePresentationLevel
        let renderPosition: SpatialPoint?
        let summary: String?
    }

    let workspaceLevel: WorkspacePresentationLevel
    let nodeIntents: [UUID: NodeIntent]
    let islands: [FocusIslandSummary]

    static func make(
        map: FocusMap,
        cameraIntent: FocusCameraIntent,
        selection: UUID?,
        atlasOffsets: [UUID: SpatialPoint] = [:]
    ) -> Self {
        let islands = islandSummaries(in: map)
        let workspaceLevel = workspaceLevel(
            nodeCount: map.nodes.count,
            islandCount: islands.count,
            cameraIntent: cameraIntent
        )
        let focusIsland = selection.flatMap { selected in
            islands.first { $0.nodeIDs.contains(selected) }
        }

        if workspaceLevel == .atlas {
            let positions = atlasPositions(for: islands)
            let rootIDs = Set(islands.map(\.rootID))
            return Self(
                workspaceLevel: .atlas,
                nodeIntents: Dictionary(uniqueKeysWithValues: map.nodes.map { node in
                    guard rootIDs.contains(node.id),
                          let island = islands.first(where: { $0.rootID == node.id }) else {
                        return (node.id, NodeIntent(level: .hidden, renderPosition: nil, summary: nil))
                    }
                    let base = positions[node.id] ?? node.position
                    let offset = atlasOffsets[node.id] ?? .zero
                    return (
                        node.id,
                        NodeIntent(
                            level: .atlas,
                            renderPosition: SpatialPoint(x: base.x + offset.x, y: base.y + offset.y),
                            summary: island.detailText
                        )
                    )
                }),
                islands: islands
            )
        }

        let nodeIntents = Dictionary(uniqueKeysWithValues: map.nodes.map { node in
            let level: NodePresentationLevel
            if let focusIsland, !focusIsland.nodeIDs.contains(node.id) {
                level = .hidden
            } else if let selection {
                level = focusRelativeLevel(for: node, selection: selection, map: map)
            } else {
                level = unfocusedLevel(for: node, workspaceLevel: workspaceLevel, map: map)
            }
            return (node.id, NodeIntent(level: level, renderPosition: nil, summary: nil))
        })
        return Self(workspaceLevel: workspaceLevel, nodeIntents: nodeIntents, islands: islands)
    }

    private static func workspaceLevel(
        nodeCount: Int,
        islandCount: Int,
        cameraIntent: FocusCameraIntent
    ) -> WorkspacePresentationLevel {
        let isFocused: Bool = switch cameraIntent.mode {
        case .framed, .search: true
        case .canonical, .free, .overview: false
        }
        if nodeCount >= 120 && !isFocused {
            return .atlas
        }
        if nodeCount >= 48,
           islandCount > 1,
           cameraIntent.mode == .overview || cameraIntent.pose.distance >= 17 {
            return .atlas
        }
        if cameraIntent.pose.distance >= 11.5 { return .branch }
        return .detail
    }

    private static func focusRelativeLevel(
        for node: FocusNode,
        selection: UUID,
        map: FocusMap
    ) -> NodePresentationLevel {
        if node.id == selection || map.ancestors(of: selection).contains(node.id) { return .full }
        if let generation = descendantGeneration(of: node.id, from: selection, map: map) {
            switch generation {
            case 1: return .full
            case 2: return .compact
            case 3: return .reduced
            case 4: return .miniature
            default: return .silhouette
            }
        }
        if let selectedParent = map.node(id: selection)?.parentID,
           node.parentID == selectedParent {
            return .compact
        }
        return .silhouette
    }

    private static func unfocusedLevel(
        for node: FocusNode,
        workspaceLevel: WorkspacePresentationLevel,
        map: FocusMap
    ) -> NodePresentationLevel {
        let depth = map.ancestors(of: node.id).count
        switch workspaceLevel {
        case .atlas:
            return node.parentID == nil ? .atlas : .hidden
        case .branch:
            if depth <= 1 { return .full }
            switch depth {
            case 2: return .compact
            case 3: return .reduced
            case 4: return .miniature
            default: return .silhouette
            }
        case .detail:
            switch depth {
            case ...2: return .full
            case 3: return .compact
            case 4: return .reduced
            case 5: return .miniature
            default: return .silhouette
            }
        }
    }

    private static func descendantGeneration(
        of candidate: UUID,
        from ancestor: UUID,
        map: FocusMap
    ) -> Int? {
        let ancestors = map.ancestors(of: candidate)
        guard let index = ancestors.firstIndex(of: ancestor) else { return nil }
        return index + 1
    }

    private static func islandSummaries(in map: FocusMap) -> [FocusIslandSummary] {
        let validIDs = Set(map.nodes.map(\.id))
        let roots = map.nodes.filter { node in
            node.parentID == nil || !validIDs.contains(node.parentID!)
        }.sorted(by: spatiallyPrecedes)
        var visited: Set<UUID> = []
        var summaries: [FocusIslandSummary] = []

        for candidate in roots + map.nodes.sorted(by: spatiallyPrecedes) where !visited.contains(candidate.id) {
            let hierarchyIsland = map.descendants(of: candidate.id).union([candidate.id])
            guard !hierarchyIsland.isEmpty else { continue }
            visited.formUnion(hierarchyIsland)
            let nodes = map.nodes.filter { hierarchyIsland.contains($0.id) }
            let root = candidate
            summaries.append(FocusIslandSummary(
                rootID: root.id,
                title: root.title,
                thoughtCount: nodes.count,
                minimumAttention: nodes.map(\.attention).min() ?? root.attention,
                maximumAttention: nodes.map(\.attention).max() ?? root.attention,
                urgentCount: nodes.count { $0.urgency != .none },
                nodeIDs: hierarchyIsland
            ))
        }
        return summaries.sorted {
            let titleOrder = $0.title.localizedStandardCompare($1.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return $0.rootID.uuidString < $1.rootID.uuidString
        }
    }

    private static func atlasPositions(for islands: [FocusIslandSummary]) -> [UUID: SpatialPoint] {
        guard !islands.isEmpty else { return [:] }
        let columns = min(4, max(1, Int(ceil(sqrt(Double(islands.count))))))
        let rows = Int(ceil(Double(islands.count) / Double(columns)))
        let horizontalSpacing = 2.20
        let verticalSpacing = 1.55
        var positions: [UUID: SpatialPoint] = [:]
        for (index, island) in islands.enumerated() {
            let row = index / columns
            let column = index % columns
            let countInRow = min(columns, islands.count - row * columns)
            positions[island.rootID] = SpatialPoint(
                x: (Double(column) - Double(countInRow - 1) / 2) * horizontalSpacing,
                y: (Double(rows - 1) / 2 - Double(row)) * verticalSpacing
            )
        }
        return positions
    }

    private static func spatiallyPrecedes(_ lhs: FocusNode, _ rhs: FocusNode) -> Bool {
        if lhs.position.y != rhs.position.y { return lhs.position.y > rhs.position.y }
        if lhs.position.x != rhs.position.x { return lhs.position.x < rhs.position.x }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
