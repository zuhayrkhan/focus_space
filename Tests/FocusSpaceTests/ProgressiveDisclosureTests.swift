import XCTest
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
