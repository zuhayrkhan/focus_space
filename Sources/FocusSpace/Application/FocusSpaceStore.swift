import Combine
import Foundation

@MainActor
final class FocusSpaceStore: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case today = "Near me"
        case all = "Everything"
        case parked = "Parked"
        var id: Self { self }
    }

    @Published private(set) var map: FocusMap
    @Published var selection: UUID?
    @Published var filter: Filter = .today
    @Published var searchText = ""
    @Published var isSearching = false
    @Published var editingNodeID: UUID?
    @Published private(set) var hoveredNodeID: UUID?
    @Published private(set) var cameraIntent: FocusCameraIntent = .canonical
    @Published private(set) var demoScene: DemoScene?
    @Published private(set) var persistenceMessage: String?

    private let repository: any FocusMapRepository
    private var undoMaps: [FocusMap] = []
    private var redoMaps: [FocusMap] = []
    private var isInteracting = false
    private var saveTask: Task<Void, Never>?
    private var personalMapBeforeDemo: FocusMap?

    init(repository: any FocusMapRepository = JSONFocusMapRepository()) {
        self.repository = repository
        do {
            map = try repository.load() ?? Self.sampleMap
        } catch {
            map = Self.sampleMap
            persistenceMessage = "Couldn’t open the saved space: \(error.localizedDescription)"
        }
    }

    var selectedNode: FocusNode? {
        selection.flatMap(map.node(id:))
    }

    var canUndo: Bool { !undoMaps.isEmpty }
    var canRedo: Bool { !redoMaps.isEmpty }
    var isPreviewingDemo: Bool { demoScene != nil }
    var canFrameSelection: Bool { selection != nil }
    var canArrange: Bool { map.nodes.count > 1 }

    var sceneSnapshot: FocusSceneSnapshot {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextID = hoveredNodeID ?? selection
        let contextIDs = contextID.map(contextNodeIDs(around:)) ?? []
        let ancestryIDs = Set(contextID.map(map.ancestors(of:)) ?? [])
        let items = map.nodes.map { node in
            let includedByFilter: Bool = switch filter {
            case .today: node.attention >= 0.42
            case .all: true
            case .parked: node.attention < 0.42
            }
            let includedBySearch = query.isEmpty || node.title.localizedCaseInsensitiveContains(query)
            return FocusSceneSnapshot.Item(
                id: node.id,
                title: node.title,
                notes: node.notes,
                kind: node.kind,
                position: node.position,
                attention: node.attention,
                parentID: node.parentID,
                hierarchyDepth: hierarchyDepth(of: node),
                urgency: node.urgency,
                isEnabled: node.isEnabled,
                isSelected: selection == node.id,
                isDimmed: !includedByFilter || !includedBySearch,
                isHovered: hoveredNodeID == node.id,
                contextRole: contextRole(
                    for: node.id,
                    contextID: contextID,
                    contextIDs: contextIDs,
                    ancestryIDs: ancestryIDs
                )
            )
        }
        return FocusSceneSnapshot(
            items: items,
            relationships: relationships(
                items: items,
                contextID: contextID,
                contextIDs: contextIDs,
                ancestryIDs: ancestryIDs
            )
        )
    }

    func select(_ id: UUID?) {
        let selectionChanged = selection != id
        withAnimationIntent { selection = id }
        guard selectionChanged, let id, !map.descendants(of: id).isEmpty else { return }
        frameBranch(id)
    }

    func setCameraPose(_ pose: FocusCameraIntent.Pose, animated: Bool = false) {
        cameraIntent = FocusCameraIntent(
            pose: pose.bounded(),
            mode: .free,
            revision: cameraIntent.revision + 1,
            isAnimated: animated
        )
    }

    func panCamera(horizontal: Double, vertical: Double, from origin: FocusCameraIntent.Pose? = nil) {
        var pose = origin ?? cameraIntent.pose
        let scale = pose.distance / 520
        pose.target.x -= horizontal * scale
        pose.target.y += vertical * scale
        setCameraPose(pose)
    }

    func orbitCamera(horizontal: Double, vertical: Double, from origin: FocusCameraIntent.Pose? = nil) {
        setCameraPose(orbitCameraPose(horizontal: horizontal, vertical: vertical, from: origin))
    }

    func orbitCameraPose(
        horizontal: Double,
        vertical: Double,
        from origin: FocusCameraIntent.Pose? = nil
    ) -> FocusCameraIntent.Pose {
        var pose = origin ?? cameraIntent.pose
        pose.yaw -= horizontal * 0.28
        pose.pitch += vertical * 0.22
        return pose.bounded()
    }

    func zoomCamera(by factor: Double, from origin: FocusCameraIntent.Pose? = nil, animated: Bool = false) {
        setCameraPose(zoomCameraPose(by: factor, from: origin), animated: animated)
    }

    func zoomCameraPose(
        by factor: Double,
        from origin: FocusCameraIntent.Pose? = nil
    ) -> FocusCameraIntent.Pose {
        var pose = origin ?? cameraIntent.pose
        pose.distance /= min(max(factor, 0.25), 4)
        return pose.bounded()
    }

    func frameSelection() {
        guard let selection else { return }
        frameBranch(selection)
    }

    private func frameBranch(_ id: UUID) {
        guard let selected = map.node(id: id) else { return }
        let ids = map.descendants(of: id).union([id])
        let nodes = map.nodes.filter { ids.contains($0.id) }
        let minX = nodes.map(\.position.x).min() ?? selected.position.x
        let maxX = nodes.map(\.position.x).max() ?? selected.position.x
        let minY = nodes.map(\.position.y).min() ?? selected.position.y
        let maxY = nodes.map(\.position.y).max() ?? selected.position.y
        let attention = nodes.map(\.attention).reduce(0, +) / Double(max(nodes.count, 1))
        let span = max(maxX - minX, (maxY - minY) * 1.6)
        let desiredDistance = min(max(5.4 + span * 0.72, 5.4), 12.5)
        let center = SpatialPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let selectedBias = 0.30
        let pose = FocusCameraIntent.Pose(
            target: SpatialPoint(
                x: center.x + (selected.position.x - center.x) * selectedBias,
                y: center.y + (selected.position.y - center.y) * selectedBias
            ),
            targetAttention: attention,
            yaw: cameraIntent.pose.yaw,
            pitch: cameraIntent.pose.pitch,
            distance: max(4.2, min(desiredDistance, cameraIntent.pose.distance * 0.82))
        ).bounded()
        cameraIntent = FocusCameraIntent(
            pose: pose,
            mode: .framed(id),
            revision: cameraIntent.revision + 1,
            isAnimated: true
        )
    }

    func resetCamera(animated: Bool = true) {
        cameraIntent = FocusCameraIntent(
            pose: .canonical,
            mode: .canonical,
            revision: cameraIntent.revision + 1,
            isAnimated: animated
        )
    }

    func hover(_ id: UUID?) {
        guard hoveredNodeID != id else { return }
        hoveredNodeID = id
    }

    func preview(_ scene: DemoScene?) {
        if let scene {
            if personalMapBeforeDemo == nil { personalMapBeforeDemo = map }
            demoScene = scene
            map = scene.map
        } else if let personalMapBeforeDemo {
            demoScene = nil
            map = personalMapBeforeDemo
            self.personalMapBeforeDemo = nil
        }
        selection = nil
        hoveredNodeID = nil
        resetCamera(animated: true)
        editingNodeID = nil
        undoMaps.removeAll()
        redoMaps.removeAll()
    }

    func beginRenaming(_ id: UUID) {
        selection = id
        editingNodeID = id
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, map.node(id: id)?.title != trimmed else {
            editingNodeID = nil
            return
        }
        mutate {
            $0.updateNode(id: id) { node in
                node.title = trimmed
                node.updatedAt = .now
            }
        }
        editingNodeID = nil
    }

    func move(_ id: UUID, to point: SpatialPoint) {
        mutate(recordingUndo: !isInteracting) { $0.updateNode(id: id) { $0.move(to: point) } }
    }

    func setAttention(_ id: UUID, to attention: Double) {
        mutate(recordingUndo: !isInteracting) { $0.updateNode(id: id) { $0.setAttention(attention) } }
    }

    func shiftAttention(_ id: UUID, by delta: Double) {
        guard let node = map.node(id: id) else { return }
        setAttention(id, to: node.attention + delta)
    }

    func arrangeMindMap() {
        let positions = MindMapArranger.positions(for: map)
        mutate { map in
            for index in map.nodes.indices {
                guard let position = positions[map.nodes[index].id] else { continue }
                map.nodes[index].move(to: position)
            }
        }
        frameEntireMap()
    }

    private func frameEntireMap() {
        guard !map.nodes.isEmpty else { return }
        let minX = map.nodes.map(\.position.x).min() ?? 0
        let maxX = map.nodes.map(\.position.x).max() ?? 0
        let minY = map.nodes.map(\.position.y).min() ?? 0
        let maxY = map.nodes.map(\.position.y).max() ?? 0
        let attention = map.nodes.map(\.attention).reduce(0, +) / Double(map.nodes.count)
        let span = max(maxX - minX, (maxY - minY) * 1.6)
        let pose = FocusCameraIntent.Pose(
            target: SpatialPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2),
            targetAttention: attention,
            yaw: 0,
            pitch: 0,
            distance: min(max(7 + span * 0.72, 9.8), 18)
        ).bounded()
        cameraIntent = FocusCameraIntent(
            pose: pose,
            mode: .overview,
            revision: cameraIntent.revision + 1,
            isAnimated: true
        )
    }

    func setKind(_ id: UUID, to kind: FocusNodeKind) {
        mutate { $0.updateNode(id: id) { node in
            node.kind = kind
            node.updatedAt = .now
        } }
    }

    func setNotes(_ id: UUID, to notes: String) {
        mutate(recordingUndo: !isInteracting) { map in
            map.updateNode(id: id) { node in
                node.notes = notes
                node.updatedAt = .now
            }
        }
    }

    func setUrgency(_ id: UUID, to urgency: FocusNodeUrgency) {
        mutate { $0.updateNode(id: id) { node in
            node.urgency = urgency
            node.updatedAt = .now
        } }
    }

    func setEnabled(_ id: UUID, to isEnabled: Bool) {
        mutate { $0.updateNode(id: id) { node in
            node.isEnabled = isEnabled
            node.updatedAt = .now
        } }
    }

    func beginInteraction() {
        guard !isInteracting else { return }
        isInteracting = true
        undoMaps.append(map)
        if undoMaps.count > 100 { undoMaps.removeFirst() }
        redoMaps.removeAll()
    }

    func endInteraction() {
        guard isInteracting else { return }
        isInteracting = false
        if undoMaps.last == map { undoMaps.removeLast() }
    }

    @discardableResult
    func addChild(to parentID: UUID?) -> UUID {
        let parent = parentID.flatMap(map.node(id:))
        let node = FocusNode(
            title: parent == nil ? "New thought" : "New direction",
            kind: parent == nil ? .project : .task,
            position: SpatialPoint(
                x: (parent?.position.x ?? 0) + 1.45,
                y: (parent?.position.y ?? 0) - 0.85
            ),
            attention: parent?.attention ?? 0.65,
            parentID: parentID
        )
        mutate { $0.nodes.append(node) }
        selection = node.id
        editingNodeID = node.id
        return node.id
    }

    func addSibling(to id: UUID) {
        addChild(to: map.node(id: id)?.parentID)
    }

    func duplicate(_ id: UUID) {
        guard var copy = map.node(id: id) else { return }
        copy = FocusNode(
            title: "\(copy.title) copy",
            notes: copy.notes,
            kind: copy.kind,
            position: SpatialPoint(x: copy.position.x + 0.45, y: copy.position.y - 0.45),
            attention: copy.attention,
            parentID: copy.parentID,
            urgency: copy.urgency,
            isEnabled: copy.isEnabled
        )
        mutate { $0.nodes.append(copy) }
        selection = copy.id
    }

    func delete(_ id: UUID) {
        mutate { $0.removeNodeAndDescendants(id: id) }
        selection = nil
    }

    func undo() {
        guard let previous = undoMaps.popLast() else { return }
        redoMaps.append(map)
        map = previous
        validateSelection()
        scheduleSave()
    }

    func redo() {
        guard let next = redoMaps.popLast() else { return }
        undoMaps.append(map)
        map = next
        validateSelection()
        scheduleSave()
    }

    private func mutate(recordingUndo: Bool = true, _ change: (inout FocusMap) -> Void) {
        let previous = map
        change(&map)
        guard previous != map else { return }
        if recordingUndo {
            undoMaps.append(previous)
            if undoMaps.count > 100 { undoMaps.removeFirst() }
            redoMaps.removeAll()
        }
        scheduleSave()
    }

    private func scheduleSave() {
        guard demoScene == nil else { return }
        saveTask?.cancel()
        let repository = repository
        let map = map
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            do {
                try repository.save(map)
                persistenceMessage = nil
            } catch {
                persistenceMessage = "Autosave paused: \(error.localizedDescription)"
            }
        }
    }

    private func validateSelection() {
        if let selection, map.node(id: selection) == nil { self.selection = nil }
    }

    private func hierarchyDepth(of node: FocusNode) -> Int {
        var depth = 0
        var parentID = node.parentID
        var visited: Set<UUID> = [node.id]
        while let currentID = parentID,
              !visited.contains(currentID),
              let parent = map.node(id: currentID) {
            depth += 1
            visited.insert(currentID)
            parentID = parent.parentID
        }
        return depth
    }

    private func contextNodeIDs(around id: UUID) -> Set<UUID> {
        var result = map.descendants(of: id)
        result.formUnion(map.ancestors(of: id))
        result.insert(id)
        if let parentID = map.node(id: id)?.parentID {
            result.formUnion(map.nodes.lazy.filter { $0.parentID == parentID }.map(\.id))
        }
        return result
    }

    private func contextRole(
        for id: UUID,
        contextID: UUID?,
        contextIDs: Set<UUID>,
        ancestryIDs: Set<UUID>
    ) -> FocusSceneSnapshot.ContextRole {
        guard let contextID else { return .none }
        if id == contextID || ancestryIDs.contains(id) { return .direct }
        if contextIDs.contains(id) { return .branch }
        return .subdued
    }

    private func relationships(
        items: [FocusSceneSnapshot.Item],
        contextID: UUID?,
        contextIDs: Set<UUID>,
        ancestryIDs: Set<UUID>
    ) -> [FocusSceneSnapshot.Relationship] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var result: [FocusSceneSnapshot.Relationship] = []

        for child in items {
            guard let parentID = child.parentID, let parent = byID[parentID] else { continue }
            let emphasis = relationshipEmphasis(
                sourceID: parentID,
                targetID: child.id,
                kind: .hierarchy,
                contextID: contextID,
                contextIDs: contextIDs,
                ancestryIDs: ancestryIDs
            )
            result.append(FocusSceneSnapshot.Relationship(
                id: .init(kind: .hierarchy, sourceID: parentID, targetID: child.id),
                sourceID: parentID,
                targetID: child.id,
                kind: .hierarchy,
                emphasis: emphasis,
                attention: (parent.attention + child.attention) / 2,
                isDimmed: parent.isDimmed || child.isDimmed
            ))
        }

        var seenCrossLinks: Set<Set<UUID>> = []
        for node in map.nodes {
            for relatedID in node.relatedNodeIDs where byID[relatedID] != nil {
                let pair: Set<UUID> = [node.id, relatedID]
                guard pair.count == 2, seenCrossLinks.insert(pair).inserted,
                      let source = byID[node.id], let target = byID[relatedID] else { continue }
                let ordered = [node.id, relatedID].sorted { $0.uuidString < $1.uuidString }
                let emphasis = relationshipEmphasis(
                    sourceID: ordered[0],
                    targetID: ordered[1],
                    kind: .crossLink,
                    contextID: contextID,
                    contextIDs: contextIDs,
                    ancestryIDs: ancestryIDs
                )
                result.append(FocusSceneSnapshot.Relationship(
                    id: .init(kind: .crossLink, sourceID: ordered[0], targetID: ordered[1]),
                    sourceID: ordered[0],
                    targetID: ordered[1],
                    kind: .crossLink,
                    emphasis: emphasis,
                    attention: (source.attention + target.attention) / 2,
                    isDimmed: source.isDimmed || target.isDimmed
                ))
            }
        }
        return result
    }

    private func relationshipEmphasis(
        sourceID: UUID,
        targetID: UUID,
        kind: FocusSceneSnapshot.Relationship.Kind,
        contextID: UUID?,
        contextIDs: Set<UUID>,
        ancestryIDs: Set<UUID>
    ) -> FocusSceneSnapshot.Relationship.Emphasis {
        guard let contextID else { return .standard }
        if sourceID == contextID || targetID == contextID { return .direct }
        if kind == .hierarchy,
           ancestryIDs.contains(sourceID),
           ancestryIDs.contains(targetID) || targetID == contextID {
            return .direct
        }
        if contextIDs.contains(sourceID), contextIDs.contains(targetID) { return .branch }
        return .subdued
    }

    private func withAnimationIntent(_ change: () -> Void) { change() }

    private static var sampleMap: FocusMap {
        let launch = FocusNode(
            title: "Shape the first release",
            notes: "A calm spatial home for deciding what deserves attention now.",
            kind: .project,
            position: SpatialPoint(x: 0, y: 0.55),
            attention: 0.93
        )
        let prototype = FocusNode(title: "Make depth feel natural", kind: .group, position: SpatialPoint(x: -1.65, y: -0.65), attention: 0.8, parentID: launch.id)
        let conversations = FocusNode(title: "Talk to early explorers", position: SpatialPoint(x: 1.65, y: -0.7), attention: 0.62, parentID: launch.id, urgency: .soon)
        let later = FocusNode(title: "Shared spaces", kind: .someday, position: SpatialPoint(x: 2.7, y: 1.15), attention: 0.18)
        return FocusMap(nodes: [launch, prototype, conversations, later])
    }
}
