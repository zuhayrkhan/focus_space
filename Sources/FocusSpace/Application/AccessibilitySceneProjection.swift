import Foundation

struct AccessibilitySceneProjection: Equatable, Sendable {
    let items: [FocusSceneSnapshot.Item]
    let relationships: [FocusSceneSnapshot.Relationship]
    let omittedItemCount: Int

    static func make(
        snapshot: FocusSceneSnapshot,
        map: FocusMap,
        selection: UUID?,
        maximumSpatialItems: Int = 48
    ) -> Self {
        guard snapshot.items.count > maximumSpatialItems else {
            return Self(
                items: snapshot.items,
                relationships: snapshot.relationships,
                omittedItemCount: 0
            )
        }

        let contextIDs: Set<UUID> = selection.map { selected in
            Set(map.ancestors(of: selected))
                .union(map.descendants(of: selected))
                .union([selected])
        } ?? Set()
        let ordered = snapshot.items.sorted { lhs, rhs in
            let lhsPriority = priority(of: lhs, contextIDs: contextIDs)
            let rhsPriority = priority(of: rhs, contextIDs: contextIDs)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            if lhs.hierarchyDepth != rhs.hierarchyDepth { return lhs.hierarchyDepth < rhs.hierarchyDepth }
            if lhs.position.y != rhs.position.y { return lhs.position.y > rhs.position.y }
            if lhs.position.x != rhs.position.x { return lhs.position.x < rhs.position.x }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let contextItems = ordered.filter {
            priority(of: $0, contextIDs: contextIDs) < 8
        }
        let items = Array(contextItems.prefix(maximumSpatialItems))
        let includedIDs = Set(items.map(\.id))
        let relationships = snapshot.relationships.filter {
            includedIDs.contains($0.sourceID) && includedIDs.contains($0.targetID)
        }
        return Self(
            items: items,
            relationships: relationships,
            omittedItemCount: snapshot.items.count - items.count
        )
    }

    private static func priority(
        of item: FocusSceneSnapshot.Item,
        contextIDs: Set<UUID>
    ) -> Int {
        if item.isSelected { return 0 }
        if item.contextRole == .direct { return 1 }
        if item.contextRole == .branch || contextIDs.contains(item.id) { return 2 }
        return switch item.presentationLevel {
        case .atlas, .full: 3
        case .compact: 4
        case .reduced: 5
        case .miniature: 6
        case .silhouette: 7
        case .hidden: 8
        }
    }
}
