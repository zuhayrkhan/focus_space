import XCTest
import RealityKit
@testable import FocusSpace

final class ProgressiveDisclosureTests: XCTestCase {
    func testGuideCoversTheFourPartsOfTheSpatialGrammar() {
        XCTAssertEqual(SpatialGuideStep.allCases, [.depth, .hierarchy, .branchMovement, .gravity])
        for step in SpatialGuideStep.allCases {
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertFalse(step.explanation.isEmpty)
        }
    }

    func testContextualHintsDisappearAsInteractionsSucceed() {
        var progress = SpatialLearningProgress()
        XCTAssertTrue(progress.nextHint?.contains("Click") == true)

        progress.record(.selectedThought)
        XCTAssertTrue(progress.nextHint?.contains("Two-finger") == true)

        progress.record(.changedDepth)
        XCTAssertTrue(progress.nextHint?.contains("empty space") == true)

        progress.record(.navigatedUniverse)
        XCTAssertNil(progress.nextHint)
    }

    @MainActor
    func testSearchFramesMatchesWithoutChangingTheirAttention() throws {
        let target = FocusNode(
            title: "Needle review",
            notes: "The spatial result",
            position: SpatialPoint(x: 3, y: -2),
            attention: 0.31
        )
        let unrelated = FocusNode(
            title: "Haystack",
            position: SpatialPoint(x: -3, y: 2),
            attention: 0.79
        )
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = JSONFocusMapRepository(fileURL: folder.appending(path: "map.json"))
        try repository.save(FocusMap(nodes: [target, unrelated]))
        let store = FocusSpaceStore(repository: repository)

        store.updateSearchText("spatial result")

        XCTAssertEqual(store.searchResultCount, 1)
        XCTAssertEqual(store.cameraIntent.mode, .search)
        XCTAssertEqual(store.cameraIntent.pose.target, target.position)
        XCTAssertEqual(store.map.node(id: target.id)?.attention, 0.31)
        let items = Dictionary(uniqueKeysWithValues: store.sceneSnapshot.items.map { ($0.id, $0) })
        XCTAssertFalse(try XCTUnwrap(items[target.id]).isDimmed)
        XCTAssertTrue(try XCTUnwrap(items[unrelated.id]).isDimmed)
    }

    @MainActor
    func testSearchTraversesResultsAndCommitKeepsTheChosenContext() throws {
        let first = FocusNode(title: "Shared alpha", position: SpatialPoint(x: -2, y: 2))
        let second = FocusNode(title: "Shared beta", position: SpatialPoint(x: 2, y: -2))
        let store = try makeStore(nodes: [first, second])

        store.beginSearch()
        store.updateSearchText("shared")

        XCTAssertTrue(store.isSearching)
        XCTAssertEqual(store.searchResultCount, 2)
        XCTAssertEqual(store.searchResultPosition, 1)
        XCTAssertEqual(store.selectedNode?.id, first.id)
        XCTAssertEqual(store.cameraIntent.mode, .search)

        store.selectSearchResult(by: 1)
        XCTAssertEqual(store.searchResultPosition, 2)
        XCTAssertEqual(store.selectedNode?.id, second.id)

        store.commitSearchResult()
        XCTAssertFalse(store.isSearching)
        XCTAssertEqual(store.selectedNode?.id, second.id)
        XCTAssertEqual(store.cameraIntent.mode, .framed(second.id))
        XCTAssertEqual(store.viewContextTitle, "Branch · Shared beta")
        XCTAssertEqual(store.viewContextReturnTitle, "Previous view")
    }

    @MainActor
    func testCancellingSearchRestoresSelectionAndCamera() throws {
        let parent = FocusNode(title: "Parent", position: SpatialPoint(x: -1, y: 1))
        let child = FocusNode(title: "Child", position: SpatialPoint(x: -2, y: 0), parentID: parent.id)
        let match = FocusNode(title: "Needle", position: SpatialPoint(x: 4, y: -3))
        let store = try makeStore(nodes: [parent, child, match])
        store.select(parent.id)
        let origin = store.cameraIntent

        store.beginSearch()
        store.updateSearchText("needle")
        XCTAssertEqual(store.selection, match.id)

        store.cancelSearch()
        XCTAssertFalse(store.isSearching)
        XCTAssertEqual(store.selection, parent.id)
        XCTAssertEqual(store.cameraIntent.pose, origin.pose)
        XCTAssertEqual(store.cameraIntent.mode, origin.mode)
    }

    @MainActor
    func testNoSearchResultsDoNotMoveTheCameraAndClearingRestoresOrigin() throws {
        let origin = FocusNode(title: "Origin")
        let match = FocusNode(title: "Needle", position: SpatialPoint(x: 4, y: -3))
        let store = try makeStore(nodes: [origin, match])
        store.select(origin.id)
        let startingCamera = store.cameraIntent

        store.beginSearch()
        store.updateSearchText("needle")
        let matchingCamera = store.cameraIntent
        store.updateSearchText("not present")

        XCTAssertEqual(store.searchResultCount, 0)
        XCTAssertNil(store.selection)
        XCTAssertEqual(store.cameraIntent, matchingCamera)

        store.clearSearchQuery()
        XCTAssertTrue(store.isSearching)
        XCTAssertEqual(store.selection, origin.id)
        XCTAssertEqual(store.cameraIntent.pose, startingCamera.pose)
        XCTAssertEqual(store.cameraIntent.mode, startingCamera.mode)
    }

    @MainActor
    func testFilterCountsAndArrangeNoticeExplainHiddenThoughts() throws {
        let near = FocusNode(title: "Near", attention: 0.8)
        let parked = FocusNode(title: "Parked", attention: 0.2, parentID: near.id)
        let store = try makeStore(nodes: [near, parked])

        XCTAssertEqual(store.filterCount(for: .today), 1)
        XCTAssertEqual(store.filterCount(for: .all), 2)
        XCTAssertEqual(store.filterCount(for: .parked), 1)
        XCTAssertEqual(store.hiddenNodeCount, 1)
        let snapshot = store.sceneSnapshot
        XCTAssertTrue(try XCTUnwrap(snapshot.items.first { $0.id == parked.id }).isDimmed)
        let continuity = try XCTUnwrap(snapshot.relationships.first)
        XCTAssertEqual(continuity.sourceID, near.id)
        XCTAssertEqual(continuity.targetID, parked.id)
        XCTAssertTrue(continuity.isDimmed)

        store.arrangeMindMap()
        XCTAssertEqual(
            store.visibilityNotice,
            .init(hiddenCount: 1, filter: .today)
        )
        XCTAssertTrue(store.visibilityNotice?.message.contains("1 thought is") == true)

        store.showAllThoughts()
        XCTAssertEqual(store.filter, .all)
        XCTAssertEqual(store.hiddenNodeCount, 0)
        XCTAssertNil(store.visibilityNotice)
    }

    @MainActor
    func testFramedBranchProvidesAnExplicitReturnToThePreviousView() throws {
        let parent = FocusNode(title: "Parent")
        let child = FocusNode(title: "Child", position: SpatialPoint(x: 2, y: -1), parentID: parent.id)
        let store = try makeStore(nodes: [parent, child])
        let origin = store.cameraIntent

        store.select(parent.id)
        XCTAssertEqual(store.cameraIntent.mode, .framed(parent.id))
        XCTAssertEqual(store.viewContextTitle, "Branch · Parent")
        XCTAssertEqual(store.viewContextReturnTitle, "Previous view")

        store.returnFromViewContext()
        XCTAssertEqual(store.cameraIntent.mode, origin.mode)
        XCTAssertEqual(store.cameraIntent.pose, origin.pose)
        XCTAssertNil(store.viewContextTitle)
    }

    @MainActor
    func testCommandFindRequestsAndRefocusesOneSearchSession() throws {
        let store = try makeStore(nodes: [FocusNode(title: "One")])

        store.requestSearch()
        XCTAssertTrue(store.isSearching)
        XCTAssertEqual(store.searchRequestRevision, 1)

        store.requestSearch()
        XCTAssertTrue(store.isSearching)
        XCTAssertEqual(store.searchRequestRevision, 2)
    }

    @MainActor
    func testLargeMapOpensAsReadableRootAtlas() throws {
        let store = try makeStore(nodes: [])
        store.preview(.largeMap)
        store.setFilter(.all)

        let snapshot = store.sceneSnapshot
        let roots = store.map.nodes.filter { $0.parentID == nil }
        let visible = snapshot.items.filter { $0.presentationLevel.isSpatiallyVisible }

        XCTAssertEqual(snapshot.workspacePresentationLevel, .atlas)
        XCTAssertEqual(snapshot.islands.count, roots.count)
        XCTAssertEqual(visible.count, roots.count)
        XCTAssertTrue(visible.allSatisfy { $0.presentationLevel == .atlas })
        XCTAssertTrue(visible.allSatisfy { $0.presentationSummary?.contains("attention") == true })
        XCTAssertLessThanOrEqual(store.cameraIntent.pose.distance, 14)
        XCTAssertEqual(store.viewContextTitle, "Atlas · 18 islands")
    }

    @MainActor
    func testSelectingAnAtlasIslandRevealsOnlyItsBranchWithoutChangingAttention() throws {
        let store = try makeStore(nodes: [])
        store.preview(.largeMap)
        store.setFilter(.all)
        let island = try XCTUnwrap(store.islandSummaries.first)
        let attentionBefore = Dictionary(uniqueKeysWithValues: store.map.nodes.map { ($0.id, $0.attention) })

        store.frameIsland(island.rootID)

        let snapshot = store.sceneSnapshot
        let visibleIDs = Set(snapshot.items.filter { $0.presentationLevel.isSpatiallyVisible }.map(\.id))
        XCTAssertNotEqual(snapshot.workspacePresentationLevel, .atlas)
        XCTAssertEqual(store.selection, island.rootID)
        XCTAssertEqual(visibleIDs, island.nodeIDs)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: store.map.nodes.map { ($0.id, $0.attention) }),
            attentionBefore
        )
    }

    @MainActor
    func testAtlasOptionDragKeepsTheSummaryUnderThePointerAndUndoesAsOneCommand() throws {
        let store = try makeStore(nodes: [])
        store.preview(.largeMap)
        store.setFilter(.all)
        let island = try XCTUnwrap(store.islandSummaries.first)
        let connected = store.map.connectedComponent(containing: island.rootID)
        let origins = Dictionary(uniqueKeysWithValues: store.map.nodes.compactMap { node in
            connected.contains(node.id) ? (node.id, node.position) : nil
        })
        let summaryBefore = try XCTUnwrap(
            store.sceneSnapshot.items.first { $0.id == island.rootID }?.renderPosition
        )
        let delta = SpatialPoint(x: 0.7, y: -0.4)

        store.beginInteraction()
        store.translate(connected, from: origins, by: delta)
        store.endInteraction()

        let summaryAfter = try XCTUnwrap(
            store.sceneSnapshot.items.first { $0.id == island.rootID }?.renderPosition
        )
        XCTAssertEqual(summaryAfter.x, summaryBefore.x + delta.x, accuracy: 0.001)
        XCTAssertEqual(summaryAfter.y, summaryBefore.y + delta.y, accuracy: 0.001)
        XCTAssertEqual(
            try XCTUnwrap(store.map.node(id: island.rootID)?.position.x),
            origins[island.rootID]!.x + delta.x,
            accuracy: 0.001
        )

        store.undo()
        XCTAssertEqual(
            store.sceneSnapshot.items.first { $0.id == island.rootID }?.renderPosition,
            summaryBefore
        )
        XCTAssertEqual(store.map.node(id: island.rootID)?.position, origins[island.rootID])
    }

    @MainActor
    func testFocusedDeepBranchCompactsSuccessiveGenerationsAndPromotesTraversal() throws {
        let store = try makeStore(nodes: [])
        store.preview(.deepHierarchy)
        store.setFilter(.all)
        let root = try XCTUnwrap(store.map.nodes.first { $0.title == "Release Focus Space" })
        let intelligence = try XCTUnwrap(store.map.nodes.first { $0.title == "Intelligence" })
        let search = try XCTUnwrap(store.map.nodes.first { $0.title == "Search" })
        let semanticZoom = try XCTUnwrap(store.map.nodes.first { $0.title == "Semantic zoom" })
        let focusedLeaf = try XCTUnwrap(store.map.nodes.first { $0.title == "Focus selected branch" })

        store.select(root.id)
        var items = Dictionary(uniqueKeysWithValues: store.sceneSnapshot.items.map { ($0.id, $0) })
        XCTAssertEqual(items[intelligence.id]?.presentationLevel, .full)
        XCTAssertEqual(items[search.id]?.presentationLevel, .compact)
        XCTAssertEqual(items[semanticZoom.id]?.presentationLevel, .reduced)
        XCTAssertEqual(items[focusedLeaf.id]?.presentationLevel, .miniature)

        store.select(semanticZoom.id)
        items = Dictionary(uniqueKeysWithValues: store.sceneSnapshot.items.map { ($0.id, $0) })
        XCTAssertEqual(items[semanticZoom.id]?.presentationLevel, .full)
        XCTAssertEqual(items[focusedLeaf.id]?.presentationLevel, .full)
        XCTAssertEqual(items[root.id]?.presentationLevel, .full)
    }

    @MainActor
    func testRendererUsesProgressivelySmallerEntitiesWithoutLosingHitTargets() throws {
        let store = try makeStore(nodes: [])
        store.preview(.deepHierarchy)
        store.setFilter(.all)
        let rootNode = try XCTUnwrap(store.map.nodes.first { $0.title == "Release Focus Space" })
        let compactNode = try XCTUnwrap(store.map.nodes.first { $0.title == "Search" })
        let reducedNode = try XCTUnwrap(store.map.nodes.first { $0.title == "Semantic zoom" })
        let miniatureNode = try XCTUnwrap(store.map.nodes.first { $0.title == "Focus selected branch" })
        store.select(rootNode.id)
        let renderer = RealityFocusRenderer(quality: .efficient)
        let root = renderer.makeScene()

        renderer.reconcile(root: root, snapshot: store.sceneSnapshot, reduceMotion: true)

        let full = try XCTUnwrap(root.findEntity(named: "node-\(rootNode.id.uuidString)"))
        let compact = try XCTUnwrap(root.findEntity(named: "node-\(compactNode.id.uuidString)"))
        let reduced = try XCTUnwrap(root.findEntity(named: "node-\(reducedNode.id.uuidString)"))
        let miniature = try XCTUnwrap(root.findEntity(named: "node-\(miniatureNode.id.uuidString)"))
        XCTAssertGreaterThan(full.scale.x, compact.scale.x)
        XCTAssertGreaterThan(compact.scale.x, reduced.scale.x)
        XCTAssertGreaterThan(reduced.scale.x, miniature.scale.x)
        XCTAssertNotNil(compact.findEntity(named: "semantic-hit-target"))
        XCTAssertNotNil(reduced.findEntity(named: "semantic-hit-target"))
        XCTAssertNotNil(miniature.findEntity(named: "semantic-hit-target"))
        for node in [full, compact, reduced, miniature] {
            let label = try XCTUnwrap(node.findEntity(named: "node-label"))
            XCTAssertGreaterThan(label.visualBounds(relativeTo: label).extents.x, 0)
        }
    }

    func testPresentationLevelsTaperScaleAndTextAcrossFiveVisibleStages() {
        let levels: [NodePresentationLevel] = [.full, .compact, .reduced, .miniature, .silhouette]

        XCTAssertEqual(Set(levels.map(\.maximumLabelCharacters)).count, levels.count)
        for pair in zip(levels, levels.dropFirst()) {
            XCTAssertGreaterThan(pair.0.scale, pair.1.scale)
            XCTAssertGreaterThan(pair.0.labelScale, pair.1.labelScale)
            XCTAssertGreaterThan(pair.0.labelOpacity, pair.1.labelOpacity)
            XCTAssertGreaterThan(pair.0.maximumLabelCharacters, pair.1.maximumLabelCharacters)
        }
    }

    @MainActor
    func testFocusModeQuietsOnlyUnrelatedBranchesAndEndsOnDeselect() throws {
        let project = FocusNode(title: "Project", kind: .project)
        let child = FocusNode(title: "Child", parentID: project.id)
        let sibling = FocusNode(title: "Sibling", parentID: project.id)
        let unrelated = FocusNode(title: "Elsewhere", kind: .project)
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = JSONFocusMapRepository(fileURL: folder.appending(path: "map.json"))
        try repository.save(FocusMap(nodes: [project, child, sibling, unrelated]))
        let store = FocusSpaceStore(repository: repository)

        store.select(child.id)
        store.toggleFocusMode()

        let items = Dictionary(uniqueKeysWithValues: store.sceneSnapshot.items.map { ($0.id, $0) })
        XCTAssertFalse(try XCTUnwrap(items[project.id]).isDimmed)
        XCTAssertFalse(try XCTUnwrap(items[child.id]).isDimmed)
        XCTAssertFalse(try XCTUnwrap(items[sibling.id]).isDimmed)
        XCTAssertTrue(try XCTUnwrap(items[unrelated.id]).isDimmed)

        store.select(nil)
        XCTAssertFalse(store.isFocusModeEnabled)
        XCTAssertTrue(store.sceneSnapshot.items.allSatisfy { !$0.isDimmed })
    }

    @MainActor
    private func makeStore(nodes: [FocusNode]) throws -> FocusSpaceStore {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = JSONFocusMapRepository(fileURL: folder.appending(path: "map.json"))
        try repository.save(FocusMap(nodes: nodes))
        return FocusSpaceStore(repository: repository)
    }
}
