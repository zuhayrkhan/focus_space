import XCTest
@testable import FocusSpace

final class GravityEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testOverdueDateProducesAnExplainableUrgentPull() {
        let node = FocusNode(
            title: "Submit review",
            attention: 0.3,
            dueDate: now.addingTimeInterval(-86_400)
        )

        let assessment = GravityEngine.assess(node, at: now)

        XCTAssertTrue(assessment.isInfluencing)
        XCTAssertEqual(assessment.attention, 0.97)
        XCTAssertEqual(assessment.urgency, .overdue)
        XCTAssertTrue(assessment.reason.localizedCaseInsensitiveContains("due date"))
    }

    func testRecentManualOverrideWinsForSevenDays() {
        let node = FocusNode(
            title: "Deliberately parked",
            attention: 0.2,
            dueDate: now.addingTimeInterval(-86_400),
            lastManualOverride: now.addingTimeInterval(-2 * 86_400)
        )

        let held = GravityEngine.assess(node, at: now)
        let released = GravityEngine.assess(node, at: now.addingTimeInterval(8 * 86_400))

        XCTAssertFalse(held.isInfluencing)
        XCTAssertEqual(held.attention, 0.2)
        XCTAssertTrue(held.reason.hasPrefix("Manual attention holds"))
        XCTAssertTrue(released.isInfluencing)
        XCTAssertEqual(released.attention, 0.97)
    }

    func testStrongestSignalWinsAndAlwaysHasAReason() {
        let node = FocusNode(
            title: "Prepare launch",
            attention: 0.2,
            dueDate: now.addingTimeInterval(20 * 86_400),
            milestoneDate: now.addingTimeInterval(2 * 86_400),
            reminderDate: now.addingTimeInterval(-60)
        )

        let assessment = GravityEngine.assess(node, at: now)

        XCTAssertTrue(assessment.isInfluencing)
        XCTAssertGreaterThan(assessment.attention, node.attention)
        XCTAssertFalse(assessment.reason.isEmpty)
        XCTAssertTrue(assessment.reason.localizedCaseInsensitiveContains("milestone"))
    }

    @MainActor
    func testStoreKeepsManualAttentionSeparateAndGravityOptIn() throws {
        let node = FocusNode(
            title: "Upcoming",
            attention: 0.25,
            dueDate: now.addingTimeInterval(2 * 86_400)
        )
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = JSONFocusMapRepository(fileURL: folder.appending(path: "map.json"))
        try repository.save(FocusMap(nodes: [node]))
        let store = FocusSpaceStore(repository: repository, nowProvider: { self.now })

        var item = try XCTUnwrap(store.sceneSnapshot.items.first)
        XCTAssertEqual(item.attention, 0.25)
        XCTAssertEqual(item.manualAttention, 0.25)
        XCTAssertFalse(item.isGravityInfluenced)

        store.setGravityEnabled(true)
        item = try XCTUnwrap(store.sceneSnapshot.items.first)
        XCTAssertGreaterThan(item.attention, 0.25)
        XCTAssertEqual(item.manualAttention, 0.25)
        XCTAssertTrue(item.isGravityInfluenced)
        XCTAssertNotNil(item.gravityReason)
        XCTAssertEqual(item.urgency, .soon)

        store.setAttention(node.id, to: 0.1)
        item = try XCTUnwrap(store.sceneSnapshot.items.first)
        XCTAssertEqual(item.attention, 0.1)
        XCTAssertEqual(item.manualAttention, 0.1)
        XCTAssertFalse(item.isGravityInfluenced)

        store.releaseManualGravityOverride(node.id)
        item = try XCTUnwrap(store.sceneSnapshot.items.first)
        XCTAssertGreaterThan(item.attention, 0.1)
        XCTAssertTrue(item.isGravityInfluenced)
    }
}
