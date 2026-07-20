import XCTest
@testable import FocusSpace

final class FocusMapTests: XCTestCase {
    func testAttentionIsAlwaysClamped() {
        var node = FocusNode(title: "A", attention: 2)
        XCTAssertEqual(node.attention, 1)
        node.setAttention(-1)
        XCTAssertEqual(node.attention, 0)
    }

    func testRemovingParentAlsoRemovesDescendantsAndRelationships() {
        let parent = FocusNode(title: "Parent")
        let child = FocusNode(title: "Child", parentID: parent.id)
        let grandchild = FocusNode(title: "Grandchild", parentID: child.id)
        let peer = FocusNode(title: "Peer", relatedNodeIDs: [child.id])
        var map = FocusMap(nodes: [parent, child, grandchild, peer])

        map.removeNodeAndDescendants(id: parent.id)

        XCTAssertEqual(map.nodes.map(\.id), [peer.id])
        XCTAssertTrue(map.nodes[0].relatedNodeIDs.isEmpty)
    }

    func testJSONRepositoryRoundTripsHumanReadableMap() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = JSONFocusMapRepository(fileURL: folder.appending(path: "map.json"))
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let node = FocusNode(
            title: "Explore depth",
            notes: "Shown when this thought is selected.",
            kind: .reference,
            attention: 0.72,
            urgency: .overdue,
            isEnabled: false,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let original = FocusMap(title: "A quiet place", nodes: [node])

        try repository.save(original)

        XCTAssertEqual(try repository.load(), original)
        let text = try String(contentsOf: repository.fileURL, encoding: .utf8)
        XCTAssertTrue(text.contains("\n"))
        XCTAssertTrue(text.contains("Explore depth"))
        XCTAssertTrue(text.contains("\"version\" : 4"))
        XCTAssertTrue(text.contains("Shown when this thought is selected."))
        XCTAssertTrue(text.contains("\"kind\" : \"reference\""))
        XCTAssertTrue(text.contains("\"urgency\" : \"overdue\""))
        XCTAssertTrue(text.contains("\"isEnabled\" : false"))
    }

    func testLegacyVersionOneJSONMigratesNodeVisualSemanticsToSafeDefaults() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = JSONFocusMapRepository(fileURL: folder.appending(path: "map.json"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let legacyJSON = """
        {
          "version": 1,
          "title": "Legacy space",
          "nodes": [{
            "id": "F0C05ACE-0001-4000-8000-000000000001",
            "title": "Existing thought",
            "position": { "x": 1.0, "y": -1.0 },
            "attention": 0.7,
            "relatedNodeIDs": [],
            "createdAt": "2027-01-15T08:00:00Z",
            "updatedAt": "2027-01-15T08:00:00Z"
          }]
        }
        """
        try Data(legacyJSON.utf8).write(to: repository.fileURL)

        let migrated = try XCTUnwrap(repository.load())

        XCTAssertEqual(migrated.version, FocusMap.currentVersion)
        XCTAssertEqual(migrated.nodes.first?.kind, .task)
        XCTAssertEqual(migrated.nodes.first?.urgency, FocusNodeUrgency.none)
        XCTAssertEqual(migrated.nodes.first?.isEnabled, true)
        XCTAssertEqual(migrated.nodes.first?.notes, "")
        XCTAssertFalse(migrated.isGravityEnabled)
        XCTAssertNil(migrated.nodes.first?.dueDate)
        XCTAssertNil(migrated.nodes.first?.milestoneDate)
        XCTAssertNil(migrated.nodes.first?.reminderDate)
        XCTAssertNil(migrated.nodes.first?.lastManualOverride)
        XCTAssertEqual(migrated.nodes.first?.gravityPreference, .inherit)
    }

    func testVersionTwoJSONPreservesVisualSemanticsAndAddsNotesDefaults() throws {
        let data = Data("""
        {
          "version": 2,
          "title": "Version two",
          "nodes": [{
            "id": "F0C05ACE-0002-4000-8000-000000000002",
            "title": "Existing group",
            "kind": "group",
            "position": { "x": 2.0, "y": -2.0 },
            "attention": 0.62,
            "relatedNodeIDs": [],
            "urgency": "soon",
            "isEnabled": false,
            "createdAt": "2027-01-15T08:00:00Z",
            "updatedAt": "2027-01-15T08:00:00Z"
          }]
        }
        """.utf8)

        let migrated = try FocusMapJSONCodec.decode(data)

        XCTAssertEqual(migrated.version, 4)
        XCTAssertEqual(migrated.title, "Version two")
        XCTAssertEqual(migrated.nodes.first?.kind, .group)
        XCTAssertEqual(migrated.nodes.first?.attention, 0.62)
        XCTAssertEqual(migrated.nodes.first?.urgency, .soon)
        XCTAssertEqual(migrated.nodes.first?.isEnabled, false)
        XCTAssertEqual(migrated.nodes.first?.notes, "")
        XCTAssertFalse(migrated.isGravityEnabled)
    }

    func testVersionThreeJSONPreservesNotesAndAddsTemporalDefaults() throws {
        let data = Data("""
        {
          "version": 3,
          "title": "Version three",
          "nodes": [{
            "id": "F0C05ACE-0003-4000-8000-000000000003",
            "title": "Documented thought",
            "notes": "Do not lose this context.",
            "kind": "reference",
            "position": { "x": -1.5, "y": 1.25 },
            "attention": 0.47,
            "relatedNodeIDs": [],
            "urgency": "none",
            "isEnabled": true,
            "createdAt": "2027-01-15T08:00:00Z",
            "updatedAt": "2027-01-15T08:00:00Z"
          }]
        }
        """.utf8)

        let migrated = try FocusMapJSONCodec.decode(data)

        XCTAssertEqual(migrated.version, 4)
        XCTAssertEqual(migrated.nodes.first?.notes, "Do not lose this context.")
        XCTAssertEqual(migrated.nodes.first?.kind, .reference)
        XCTAssertNil(migrated.nodes.first?.dueDate)
        XCTAssertNil(migrated.nodes.first?.milestoneDate)
        XCTAssertNil(migrated.nodes.first?.reminderDate)
        XCTAssertEqual(migrated.nodes.first?.gravityPreference, .inherit)
        XCTAssertFalse(migrated.isGravityEnabled)
    }

    func testVersionFourPersistsTemporalSignalsAndGravityPolicy() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = JSONFocusMapRepository(fileURL: folder.appending(path: "map.json"))
        let due = Date(timeIntervalSince1970: 1_800_086_400)
        let milestone = due.addingTimeInterval(86_400)
        let reminder = due.addingTimeInterval(-3_600)
        let override = due.addingTimeInterval(-86_400)
        let node = FocusNode(
            title: "Time-aware thought",
            attention: 0.4,
            dueDate: due,
            milestoneDate: milestone,
            reminderDate: reminder,
            lastManualOverride: override,
            gravityPreference: .enabled,
            createdAt: due,
            updatedAt: due
        )
        let original = FocusMap(nodes: [node], isGravityEnabled: true)

        try repository.save(original)
        let loaded = try XCTUnwrap(repository.load())

        XCTAssertEqual(loaded, original)
        XCTAssertEqual(loaded.version, 4)
        XCTAssertTrue(loaded.isGravityEnabled)
        XCTAssertEqual(loaded.nodes.first?.gravityPreference, .enabled)
    }

    func testNewerSchemaIsRejectedInsteadOfSilentlyLosingFields() {
        let data = Data("""
        {
          "version": 99,
          "title": "Future space",
          "nodes": []
        }
        """.utf8)

        XCTAssertThrowsError(try FocusMapJSONCodec.decode(data))
    }
}
