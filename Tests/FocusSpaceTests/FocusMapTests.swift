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
        XCTAssertTrue(text.contains("\"version\" : 2"))
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
    }
}
