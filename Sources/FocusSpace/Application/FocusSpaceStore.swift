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

    var sceneSnapshot: FocusSceneSnapshot {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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
                kind: node.kind,
                position: node.position,
                attention: node.attention,
                parentID: node.parentID,
                hierarchyDepth: hierarchyDepth(of: node),
                urgency: node.urgency,
                isEnabled: node.isEnabled,
                isSelected: selection == node.id,
                isDimmed: !includedByFilter || !includedBySearch
            )
        }
        return FocusSceneSnapshot(items: items)
    }

    func select(_ id: UUID?) {
        withAnimationIntent { selection = id }
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

    func setKind(_ id: UUID, to kind: FocusNodeKind) {
        mutate { $0.updateNode(id: id) { node in
            node.kind = kind
            node.updatedAt = .now
        } }
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

    private func withAnimationIntent(_ change: () -> Void) { change() }

    private static var sampleMap: FocusMap {
        let launch = FocusNode(title: "Shape the first release", kind: .project, position: SpatialPoint(x: 0, y: 0.55), attention: 0.93)
        let prototype = FocusNode(title: "Make depth feel natural", kind: .group, position: SpatialPoint(x: -1.65, y: -0.65), attention: 0.8, parentID: launch.id)
        let conversations = FocusNode(title: "Talk to early explorers", position: SpatialPoint(x: 1.65, y: -0.7), attention: 0.62, parentID: launch.id, urgency: .soon)
        let later = FocusNode(title: "Shared spaces", kind: .someday, position: SpatialPoint(x: 2.7, y: 1.15), attention: 0.18)
        return FocusMap(nodes: [launch, prototype, conversations, later])
    }
}
