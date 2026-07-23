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

    struct VisibilityNotice: Equatable {
        let hiddenCount: Int
        let filter: Filter

        var message: String {
            "Arrange included the whole map; \(hiddenCount) \(hiddenCount == 1 ? "thought is" : "thoughts are") quieter in \(filter.rawValue)."
        }
    }

    @Published private(set) var map: FocusMap
    @Published var selection: UUID?
    @Published private(set) var filter: Filter = .today
    @Published var searchText = ""
    @Published private(set) var isSearching = false
    @Published var isFocusModeEnabled = false
    @Published var editingNodeID: UUID?
    @Published private(set) var hoveredNodeID: UUID?
    @Published private(set) var cameraIntent: FocusCameraIntent = .canonical
    @Published private(set) var demoScene: DemoScene?
    @Published private(set) var persistenceMessage: String?
    @Published private(set) var lastSavedAt: Date?
    @Published private(set) var recoveredFromBackup = false
    @Published private(set) var lastAutosaveLatencyMilliseconds: Double?
    @Published private(set) var gravityEvaluationDate: Date
    @Published private(set) var latestInteraction: WorkspaceInteraction?
    @Published private(set) var interactionRevision = 0
    @Published private(set) var visibilityNotice: VisibilityNotice?
    @Published private(set) var searchRequestRevision = 0

    private let repository: any FocusMapRepository
    private let nowProvider: () -> Date
    private let autosaveDelay: Duration
    private var undoMaps: [FocusMap] = []
    private var redoMaps: [FocusMap] = []
    private var undoAtlasOffsets: [[UUID: SpatialPoint]] = []
    private var redoAtlasOffsets: [[UUID: SpatialPoint]] = []
    private var isInteracting = false
    private var saveTask: Task<Void, Never>?
    private var personalMapBeforeDemo: FocusMap?
    private var searchSession: SearchSession?
    private var searchResultIDs: [UUID] = []
    private var navigationReturnIntent: FocusCameraIntent?
    private var atlasOffsets: [UUID: SpatialPoint] = [:]

    private struct SearchSession {
        let selection: UUID?
        let cameraIntent: FocusCameraIntent
        let navigationReturnIntent: FocusCameraIntent?
    }

    init(
        repository: any FocusMapRepository = JSONFocusMapRepository(),
        nowProvider: @escaping () -> Date = Date.init,
        autosaveDelay: Duration = .milliseconds(350)
    ) {
        self.repository = repository
        self.nowProvider = nowProvider
        self.autosaveDelay = autosaveDelay
        gravityEvaluationDate = nowProvider()
        do {
            let outcome = try repository.loadRecovering()
            map = outcome.map ?? Self.sampleMap
            recoveredFromBackup = outcome.source == .recovery
            if recoveredFromBackup {
                persistenceMessage = "Your last valid backup was restored. The damaged primary file was left available in Storage Details."
            }
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
    var storageLocations: FocusMapStorageLocations { repository.storageLocations }
    var searchResultCount: Int { searchResultIDs.count }
    var activeSearchResultID: UUID? {
        guard isSearching else { return nil }
        return selection.flatMap { searchResultIDs.contains($0) ? $0 : nil }
    }
    var searchResultPosition: Int? {
        guard let activeSearchResultID,
              let index = searchResultIDs.firstIndex(of: activeSearchResultID) else { return nil }
        return index + 1
    }
    var hiddenNodeCount: Int { map.nodes.count - filterCount(for: filter) }
    var viewContextTitle: String? {
        if workspacePresentationLevel == .atlas {
            return "Atlas · \(islandSummaries.count) \(islandSummaries.count == 1 ? "island" : "islands")"
        }
        guard case let .framed(id) = cameraIntent.mode,
              let node = map.node(id: id) else { return nil }
        return "Branch · \(node.title)"
    }
    var canReturnFromViewContext: Bool {
        if case .framed = cameraIntent.mode { return true }
        return false
    }
    var viewContextReturnTitle: String {
        navigationReturnIntent == nil ? "Whole map" : "Previous view"
    }
    var spatialPresentation: SpatialPresentation {
        SpatialPresentation.make(
            map: map,
            cameraIntent: cameraIntent,
            selection: selection,
            atlasOffsets: atlasOffsets
        )
    }
    var workspacePresentationLevel: WorkspacePresentationLevel { spatialPresentation.workspaceLevel }
    var islandSummaries: [FocusIslandSummary] { spatialPresentation.islands }

    var sceneSnapshot: FocusSceneSnapshot {
        let presentation = spatialPresentation
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextID = hoveredNodeID ?? selection
        let contextIDs = contextID.map(contextNodeIDs(around:)) ?? []
        let ancestryIDs = Set(contextID.map(map.ancestors(of:)) ?? [])
        let items = map.nodes.map { node in
            let presentationIntent = presentation.nodeIntents[node.id]
            let gravity = gravityAssessment(for: node)
            let effectiveAttention = gravity.attention
            let includedByFilter: Bool = switch filter {
            case .today: node.attention >= 0.42
            case .all: true
            case .parked: node.attention < 0.42
            }
            let includedBySearch = query.isEmpty
                || node.title.localizedCaseInsensitiveContains(query)
                || node.notes.localizedCaseInsensitiveContains(query)
            let includedByFocus = !isFocusModeEnabled || contextIDs.contains(node.id)
            let excludedByViewFilter = query.isEmpty && !includedByFilter
            return FocusSceneSnapshot.Item(
                id: node.id,
                title: node.title,
                notes: node.notes,
                kind: node.kind,
                position: node.position,
                attention: effectiveAttention,
                manualAttention: node.attention,
                gravityReason: gravity.reason,
                isGravityInfluenced: gravity.isInfluencing,
                parentID: node.parentID,
                hierarchyDepth: hierarchyDepth(of: node),
                urgency: strongestUrgency(node.urgency, gravity.urgency),
                isEnabled: node.isEnabled,
                isSelected: selection == node.id,
                isDimmed: excludedByViewFilter || !includedBySearch || !includedByFocus,
                isHovered: hoveredNodeID == node.id,
                contextRole: contextRole(
                    for: node.id,
                    contextID: contextID,
                    contextIDs: contextIDs,
                    ancestryIDs: ancestryIDs
                ),
                presentationLevel: presentationIntent?.level ?? .full,
                renderPosition: presentationIntent?.renderPosition,
                presentationSummary: presentationIntent?.summary
            )
        }
        return FocusSceneSnapshot(
            items: items,
            relationships: relationships(
                items: items,
                contextID: contextID,
                contextIDs: contextIDs,
                ancestryIDs: ancestryIDs
            ),
            workspacePresentationLevel: presentation.workspaceLevel,
            islands: presentation.islands
        )
    }

    func select(_ id: UUID?) {
        if isSearching {
            if let id, searchResultIDs.contains(id) {
                selection = id
                commitSearchResult()
                recordInteraction(.selectedThought)
                return
            }
            cancelSearch()
        }
        let selectionChanged = selection != id
        withAnimationIntent { selection = id }
        if id != nil { recordInteraction(.selectedThought) }
        if id == nil { isFocusModeEnabled = false }
        guard selectionChanged, let id, !map.descendants(of: id).isEmpty else { return }
        frameBranch(id)
    }

    func setCameraPose(_ pose: FocusCameraIntent.Pose, animated: Bool = false) {
        navigationReturnIntent = nil
        cameraIntent = FocusCameraIntent(
            pose: pose.bounded(),
            mode: .free,
            revision: cameraIntent.revision + 1,
            isAnimated: animated
        )
    }

    func panCamera(horizontal: Double, vertical: Double, from origin: FocusCameraIntent.Pose? = nil) {
        setCameraPose(panCameraPose(horizontal: horizontal, vertical: vertical, from: origin))
        recordInteraction(.navigatedUniverse)
    }

    func panCameraPose(
        horizontal: Double,
        vertical: Double,
        from origin: FocusCameraIntent.Pose? = nil
    ) -> FocusCameraIntent.Pose {
        var pose = origin ?? cameraIntent.pose
        let scale = pose.distance / 520
        pose.target.x -= horizontal * scale
        pose.target.y += vertical * scale
        return pose.bounded()
    }

    func orbitCamera(horizontal: Double, vertical: Double, from origin: FocusCameraIntent.Pose? = nil) {
        setCameraPose(orbitCameraPose(horizontal: horizontal, vertical: vertical, from: origin))
        recordInteraction(.navigatedUniverse)
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
        recordInteraction(.navigatedUniverse)
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
        if navigationReturnIntent == nil, cameraIntent.mode != .search {
            navigationReturnIntent = cameraIntent
        }
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
            distance: max(
                FocusCameraIntent.Pose.minimumDistance,
                min(12.5, max(desiredDistance, cameraIntent.pose.distance * 0.82))
            )
        ).bounded()
        cameraIntent = FocusCameraIntent(
            pose: pose,
            mode: .framed(id),
            revision: cameraIntent.revision + 1,
            isAnimated: true
        )
    }

    func beginSearch() {
        guard !isSearching else { return }
        searchSession = SearchSession(
            selection: selection,
            cameraIntent: cameraIntent,
            navigationReturnIntent: navigationReturnIntent
        )
        searchResultIDs = []
        searchText = ""
        isSearching = true
    }

    func requestSearch() {
        beginSearch()
        searchRequestRevision += 1
    }

    func updateSearchText(_ text: String) {
        if !isSearching { beginSearch() }
        searchText = text
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResultIDs = []
            restoreSearchOrigin(keepingSession: true)
            return
        }
        let matches = map.nodes.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.notes.localizedCaseInsensitiveContains(query)
        }.sorted(by: spatiallyPrecedes)
        searchResultIDs = matches.map(\.id)
        guard let first = matches.first else {
            selection = nil
            isFocusModeEnabled = false
            return
        }
        let resultID = selection.flatMap { searchResultIDs.contains($0) ? $0 : nil } ?? first.id
        focusSearchResult(resultID)
    }

    func selectSearchResult(by offset: Int) {
        guard !searchResultIDs.isEmpty else { return }
        let current = selection.flatMap(searchResultIDs.firstIndex(of:)) ?? 0
        let next = (current + offset + searchResultIDs.count) % searchResultIDs.count
        focusSearchResult(searchResultIDs[next])
    }

    func commitSearchResult() {
        guard isSearching, let selected = activeSearchResultID else {
            cancelSearch()
            return
        }
        let origin = searchSession
        searchText = ""
        searchResultIDs = []
        searchSession = nil
        isSearching = false
        navigationReturnIntent = origin?.cameraIntent
        cameraIntent = FocusCameraIntent(
            pose: cameraIntent.pose,
            mode: .framed(selected),
            revision: cameraIntent.revision + 1,
            isAnimated: false
        )
    }

    func cancelSearch() {
        guard isSearching else { return }
        restoreSearchOrigin(keepingSession: false)
        searchText = ""
        searchResultIDs = []
        searchSession = nil
        isSearching = false
    }

    func clearSearchQuery() {
        updateSearchText("")
    }

    func toggleFocusMode() {
        guard selection != nil else {
            isFocusModeEnabled = false
            return
        }
        isFocusModeEnabled.toggle()
    }

    func selectNextThought() {
        selectRelativeThought(by: 1)
    }

    func selectPreviousThought() {
        selectRelativeThought(by: -1)
    }

    func selectParentThought() {
        guard let selection,
              let parentID = map.node(id: selection)?.parentID else { return }
        select(parentID)
    }

    func selectFirstChildThought() {
        guard let selection,
              let child = map.nodes
                .filter({ $0.parentID == selection })
                .sorted(by: spatiallyPrecedes)
                .first else { return }
        select(child.id)
    }

    func moveSelection(horizontal: Double, vertical: Double) {
        guard let selection, let node = map.node(id: selection) else { return }
        move(selection, to: SpatialPoint(x: node.position.x + horizontal, y: node.position.y + vertical))
    }

    func resetCamera(animated: Bool = true) {
        navigationReturnIntent = nil
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
        discardSearchSession()
        atlasOffsets.removeAll()
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
        isFocusModeEnabled = false
        hoveredNodeID = nil
        if map.nodes.count >= 48 {
            frameEntireMap()
        } else {
            resetCamera(animated: true)
        }
        editingNodeID = nil
        undoMaps.removeAll()
        redoMaps.removeAll()
        undoAtlasOffsets.removeAll()
        redoAtlasOffsets.removeAll()
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

    func translate(
        _ nodeIDs: Set<UUID>,
        from originPositions: [UUID: SpatialPoint],
        by delta: SpatialPoint
    ) {
        let atlasRoots = workspacePresentationLevel == .atlas
            ? islandSummaries.map(\.rootID).filter(nodeIDs.contains)
            : []
        mutate(recordingUndo: !isInteracting) { map in
            for id in nodeIDs {
                guard let origin = originPositions[id] else { continue }
                map.updateNode(id: id) {
                    $0.move(to: SpatialPoint(x: origin.x + delta.x, y: origin.y + delta.y))
                }
            }
        }
        for rootID in atlasRoots {
            let origin = atlasOffsets[rootID] ?? .zero
            atlasOffsets[rootID] = SpatialPoint(x: origin.x + delta.x, y: origin.y + delta.y)
        }
    }

    func setAttention(_ id: UUID, to attention: Double) {
        let now = nowProvider()
        mutate(recordingUndo: !isInteracting) {
            $0.updateNode(id: id) { $0.setAttention(attention, manualOverrideAt: now) }
        }
        recordInteraction(.changedDepth)
    }

    func setBranchAttention(
        rootID: UUID,
        nodeIDs: Set<UUID>,
        originAttentions: [UUID: Double],
        rootAttention: Double
    ) {
        guard let origin = originAttentions[rootID] else { return }
        let delta = rootAttention - origin
        let now = nowProvider()
        mutate(recordingUndo: !isInteracting) { map in
            for id in nodeIDs {
                guard let original = originAttentions[id] else { continue }
                map.updateNode(id: id) { $0.setAttention(original + delta, manualOverrideAt: now) }
            }
        }
        recordInteraction(.changedDepth)
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
        atlasOffsets.removeAll()
        frameEntireMap()
        let hidden = hiddenNodeCount
        visibilityNotice = hidden > 0 ? VisibilityNotice(hiddenCount: hidden, filter: filter) : nil
    }

    private func frameEntireMap() {
        guard !map.nodes.isEmpty else { return }
        navigationReturnIntent = nil
        let overviewProbe = FocusCameraIntent(
            pose: cameraIntent.pose,
            mode: .overview,
            revision: cameraIntent.revision,
            isAnimated: true
        )
        let presentation = SpatialPresentation.make(
            map: map,
            cameraIntent: overviewProbe,
            selection: nil,
            atlasOffsets: atlasOffsets
        )
        if presentation.workspaceLevel == .atlas {
            let atlasItems = presentation.nodeIntents.compactMap { id, intent -> (FocusNode, SpatialPoint)? in
                guard intent.level == .atlas,
                      let node = map.node(id: id),
                      let position = intent.renderPosition else { return nil }
                return (node, position)
            }
            guard !atlasItems.isEmpty else { return }
            let minX = atlasItems.map { $0.1.x }.min() ?? 0
            let maxX = atlasItems.map { $0.1.x }.max() ?? 0
            let minY = atlasItems.map { $0.1.y }.min() ?? 0
            let maxY = atlasItems.map { $0.1.y }.max() ?? 0
            let attention = atlasItems.map { $0.0.attention }.reduce(0, +) / Double(atlasItems.count)
            let span = max(maxX - minX, (maxY - minY) * 1.6)
            cameraIntent = FocusCameraIntent(
                pose: FocusCameraIntent.Pose(
                    target: SpatialPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2),
                    targetAttention: attention,
                    yaw: 0,
                    pitch: 0,
                    distance: min(max(8.8 + span * 0.42, 10.5), 14)
                ).bounded(),
                mode: .overview,
                revision: cameraIntent.revision + 1,
                isAnimated: true
            )
            return
        }
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
            distance: min(max(7 + span * 0.72, 9.8), FocusCameraIntent.Pose.maximumDistance)
        ).bounded()
        cameraIntent = FocusCameraIntent(
            pose: pose,
            mode: .overview,
            revision: cameraIntent.revision + 1,
            isAnimated: true
        )
    }

    private func frameNodes(_ nodes: [FocusNode], mode: FocusCameraIntent.Mode) {
        guard !nodes.isEmpty else { return }
        let minX = nodes.map(\.position.x).min() ?? 0
        let maxX = nodes.map(\.position.x).max() ?? 0
        let minY = nodes.map(\.position.y).min() ?? 0
        let maxY = nodes.map(\.position.y).max() ?? 0
        let attention = nodes.map(\.attention).reduce(0, +) / Double(nodes.count)
        let span = max(maxX - minX, (maxY - minY) * 1.6)
        let pose = FocusCameraIntent.Pose(
            target: SpatialPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2),
            targetAttention: attention,
            yaw: cameraIntent.pose.yaw,
            pitch: cameraIntent.pose.pitch,
            distance: min(max(5.2 + span * 0.72, 5.4), 14)
        ).bounded()
        cameraIntent = FocusCameraIntent(
            pose: pose,
            mode: mode,
            revision: cameraIntent.revision + 1,
            isAnimated: true
        )
    }

    func setFilter(_ filter: Filter) {
        self.filter = filter
        visibilityNotice = nil
    }

    func filterCount(for filter: Filter) -> Int {
        map.nodes.count { node in
            switch filter {
            case .today: node.attention >= 0.42
            case .all: true
            case .parked: node.attention < 0.42
            }
        }
    }

    func showAllThoughts() {
        setFilter(.all)
    }

    func dismissVisibilityNotice() {
        visibilityNotice = nil
    }

    func returnFromViewContext() {
        if let destination = navigationReturnIntent {
            navigationReturnIntent = nil
            cameraIntent = FocusCameraIntent(
                pose: destination.pose,
                mode: destination.mode,
                revision: cameraIntent.revision + 1,
                isAnimated: true
            )
        } else {
            frameEntireMap()
        }
    }

    func frameIsland(_ rootID: UUID) {
        guard islandSummaries.contains(where: { $0.rootID == rootID }) else { return }
        select(rootID)
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

    func relatedNodes(for id: UUID) -> [FocusNode] {
        guard let source = map.node(id: id) else { return [] }
        return map.nodes
            .filter { candidate in
                candidate.id != id
                    && (candidate.relatedNodeIDs.contains(id)
                        || source.relatedNodeIDs.contains(candidate.id))
            }
            .sorted(by: relationshipCandidatePrecedes)
    }

    func availableRelatedNodes(for id: UUID) -> [FocusNode] {
        guard let source = map.node(id: id) else { return [] }
        let relatedIDs = Set(relatedNodes(for: id).map(\.id))
        return map.nodes
            .filter { candidate in
                candidate.id != id
                    && !relatedIDs.contains(candidate.id)
                    && source.parentID != candidate.id
                    && candidate.parentID != source.id
            }
            .sorted(by: relationshipCandidatePrecedes)
    }

    func addRelatedNode(_ relatedID: UUID, to id: UUID) {
        guard availableRelatedNodes(for: id).contains(where: { $0.id == relatedID }) else { return }
        mutate { map in
            map.updateNode(id: id) { node in
                node.relatedNodeIDs.insert(relatedID)
                node.updatedAt = .now
            }
        }
    }

    func removeRelatedNode(_ relatedID: UUID, from id: UUID) {
        guard id != relatedID,
              map.node(id: id) != nil,
              map.node(id: relatedID) != nil else { return }
        mutate { map in
            map.updateNode(id: id) { node in
                node.relatedNodeIDs.remove(relatedID)
                node.updatedAt = .now
            }
            map.updateNode(id: relatedID) { node in
                node.relatedNodeIDs.remove(id)
                node.updatedAt = .now
            }
        }
    }

    private func relationshipCandidatePrecedes(_ lhs: FocusNode, _ rhs: FocusNode) -> Bool {
        let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
        if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
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

    func setGravityEnabled(_ isEnabled: Bool) {
        mutate { $0.isGravityEnabled = isEnabled }
        gravityEvaluationDate = nowProvider()
    }

    func setGravityPreference(_ id: UUID, to preference: GravityPreference) {
        mutate { $0.updateNode(id: id) { node in
            node.gravityPreference = preference
            node.updatedAt = nowProvider()
        } }
        gravityEvaluationDate = nowProvider()
    }

    func setDueDate(_ id: UUID, to date: Date?) {
        setTemporalSignal(id, keyPath: \.dueDate, to: date)
    }

    func setMilestoneDate(_ id: UUID, to date: Date?) {
        setTemporalSignal(id, keyPath: \.milestoneDate, to: date)
    }

    func setReminderDate(_ id: UUID, to date: Date?) {
        setTemporalSignal(id, keyPath: \.reminderDate, to: date)
    }

    func releaseManualGravityOverride(_ id: UUID) {
        mutate { $0.updateNode(id: id) { node in
            node.lastManualOverride = nil
            node.updatedAt = nowProvider()
        } }
        gravityEvaluationDate = nowProvider()
    }

    func refreshGravity() {
        gravityEvaluationDate = nowProvider()
    }

    func exportMapData() throws -> Data {
        try FocusMapJSONCodec.encode(map)
    }

    func importMapData(_ data: Data) throws {
        let imported = try FocusMapJSONCodec.decode(data)
        discardSearchSession()
        demoScene = nil
        personalMapBeforeDemo = nil
        selection = nil
        hoveredNodeID = nil
        editingNodeID = nil
        isFocusModeEnabled = false
        atlasOffsets.removeAll()
        map = imported
        undoMaps.removeAll()
        redoMaps.removeAll()
        undoAtlasOffsets.removeAll()
        redoAtlasOffsets.removeAll()
        saveImmediately()
    }

    func saveImmediately() {
        guard demoScene == nil else { return }
        saveTask?.cancel()
        do {
            try repository.save(map)
            lastSavedAt = nowProvider()
            persistenceMessage = nil
        } catch {
            persistenceMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func flushAutosave() async {
        await saveTask?.value
    }

    func dismissPersistenceMessage() {
        persistenceMessage = nil
    }

    func reportPersistenceError(_ message: String) {
        persistenceMessage = message
    }

    func gravityAssessment(for node: FocusNode) -> GravityAssessment {
        let isEnabled = switch node.gravityPreference {
        case .enabled: true
        case .disabled: false
        case .inherit: map.isGravityEnabled
        }
        guard isEnabled else {
            return GravityAssessment(
                attention: node.attention,
                urgency: node.urgency,
                reason: node.gravityPreference == .disabled
                    ? "Gravity is off for this thought."
                    : "Workspace gravity is off.",
                isInfluencing: false
            )
        }
        return GravityEngine.assess(node, at: gravityEvaluationDate)
    }

    func beginInteraction() {
        guard !isInteracting else { return }
        isInteracting = true
        undoMaps.append(map)
        undoAtlasOffsets.append(atlasOffsets)
        if undoMaps.count > 100 { undoMaps.removeFirst() }
        if undoAtlasOffsets.count > 100 { undoAtlasOffsets.removeFirst() }
        redoMaps.removeAll()
        redoAtlasOffsets.removeAll()
    }

    func endInteraction() {
        guard isInteracting else { return }
        isInteracting = false
        if undoMaps.last == map {
            undoMaps.removeLast()
            if !undoAtlasOffsets.isEmpty { undoAtlasOffsets.removeLast() }
        }
    }

    @discardableResult
    func addChild(to parentID: UUID?) -> UUID {
        let parent = parentID.flatMap(map.node(id:))
        let node = FocusNode(
            title: parent == nil ? "New thought" : "New direction",
            kind: parent == nil ? .project : .task,
            position: MindMapArranger.positionForNewChild(in: map, parentID: parentID),
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
            isEnabled: copy.isEnabled,
            dueDate: copy.dueDate,
            milestoneDate: copy.milestoneDate,
            reminderDate: copy.reminderDate,
            gravityPreference: copy.gravityPreference
        )
        mutate { $0.nodes.append(copy) }
        selection = copy.id
    }

    func delete(_ id: UUID) {
        mutate { $0.removeNodeAndDescendants(id: id) }
        selection = nil
        isFocusModeEnabled = false
    }

    func undo() {
        guard let previous = undoMaps.popLast() else { return }
        redoMaps.append(map)
        redoAtlasOffsets.append(atlasOffsets)
        map = previous
        atlasOffsets = undoAtlasOffsets.popLast() ?? [:]
        validateSelection()
        scheduleSave()
    }

    func redo() {
        guard let next = redoMaps.popLast() else { return }
        undoMaps.append(map)
        undoAtlasOffsets.append(atlasOffsets)
        map = next
        atlasOffsets = redoAtlasOffsets.popLast() ?? [:]
        validateSelection()
        scheduleSave()
    }

    private func mutate(recordingUndo: Bool = true, _ change: (inout FocusMap) -> Void) {
        let previous = map
        let previousAtlasOffsets = atlasOffsets
        change(&map)
        guard previous != map else { return }
        if recordingUndo {
            undoMaps.append(previous)
            undoAtlasOffsets.append(previousAtlasOffsets)
            if undoMaps.count > 100 { undoMaps.removeFirst() }
            if undoAtlasOffsets.count > 100 { undoAtlasOffsets.removeFirst() }
            redoMaps.removeAll()
            redoAtlasOffsets.removeAll()
        }
        scheduleSave()
    }

    private func scheduleSave() {
        guard demoScene == nil else { return }
        saveTask?.cancel()
        let repository = repository
        let map = map
        let scheduledAt = ContinuousClock.now
        saveTask = Task {
            try? await Task.sleep(for: autosaveDelay)
            guard !Task.isCancelled else { return }
            do {
                try repository.save(map)
                lastSavedAt = nowProvider()
                let elapsed = scheduledAt.duration(to: .now).components
                lastAutosaveLatencyMilliseconds = Double(elapsed.seconds) * 1_000
                    + Double(elapsed.attoseconds) / 1_000_000_000_000_000
                persistenceMessage = nil
            } catch {
                persistenceMessage = "Autosave paused: \(error.localizedDescription)"
            }
        }
    }

    private func validateSelection() {
        if let selection, map.node(id: selection) == nil {
            self.selection = nil
            isFocusModeEnabled = false
        }
    }

    private func setTemporalSignal(
        _ id: UUID,
        keyPath: WritableKeyPath<FocusNode, Date?>,
        to date: Date?
    ) {
        mutate { $0.updateNode(id: id) { node in
            node[keyPath: keyPath] = date
            node.updatedAt = nowProvider()
        } }
        gravityEvaluationDate = nowProvider()
    }

    private func strongestUrgency(
        _ manual: FocusNodeUrgency,
        _ computed: FocusNodeUrgency
    ) -> FocusNodeUrgency {
        let rank: [FocusNodeUrgency: Int] = [.none: 0, .soon: 1, .overdue: 2]
        return (rank[computed] ?? 0) > (rank[manual] ?? 0) ? computed : manual
    }

    private func recordInteraction(_ interaction: WorkspaceInteraction) {
        latestInteraction = interaction
        interactionRevision += 1
    }

    private func focusSearchResult(_ id: UUID) {
        guard let node = map.node(id: id), searchResultIDs.contains(id) else { return }
        selection = id
        isFocusModeEnabled = false
        frameNodes([node], mode: .search)
    }

    private func restoreSearchOrigin(keepingSession: Bool) {
        guard let searchSession else { return }
        selection = searchSession.selection.flatMap { map.node(id: $0) == nil ? nil : $0 }
        isFocusModeEnabled = false
        navigationReturnIntent = searchSession.navigationReturnIntent
        cameraIntent = FocusCameraIntent(
            pose: searchSession.cameraIntent.pose,
            mode: searchSession.cameraIntent.mode,
            revision: cameraIntent.revision + 1,
            isAnimated: true
        )
        if !keepingSession { self.searchSession = nil }
    }

    private func discardSearchSession() {
        searchText = ""
        searchResultIDs = []
        searchSession = nil
        isSearching = false
    }

    private func selectRelativeThought(by offset: Int) {
        let ordered = map.nodes.sorted(by: spatiallyPrecedes)
        guard !ordered.isEmpty else { return }
        guard let selection,
              let index = ordered.firstIndex(where: { $0.id == selection }) else {
            select(offset < 0 ? ordered.last?.id : ordered.first?.id)
            return
        }
        let next = (index + offset + ordered.count) % ordered.count
        select(ordered[next].id)
    }

    private func spatiallyPrecedes(_ lhs: FocusNode, _ rhs: FocusNode) -> Bool {
        if lhs.position.y != rhs.position.y { return lhs.position.y > rhs.position.y }
        if lhs.position.x != rhs.position.x { return lhs.position.x < rhs.position.x }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
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
            guard child.presentationLevel.isSpatiallyVisible,
                  let parentID = child.parentID,
                  let parent = byID[parentID],
                  parent.presentationLevel.isSpatiallyVisible else { continue }
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
                      let source = byID[node.id], source.presentationLevel.isSpatiallyVisible,
                      let target = byID[relatedID], target.presentationLevel.isSpatiallyVisible else { continue }
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
