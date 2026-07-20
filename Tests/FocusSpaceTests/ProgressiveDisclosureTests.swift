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
}
