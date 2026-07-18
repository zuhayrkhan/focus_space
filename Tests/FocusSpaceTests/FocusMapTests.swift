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
            attention: 0.72,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let original = FocusMap(title: "A quiet place", nodes: [node])

        try repository.save(original)

        XCTAssertEqual(try repository.load(), original)
        let text = try String(contentsOf: repository.fileURL, encoding: .utf8)
        XCTAssertTrue(text.contains("\n"))
        XCTAssertTrue(text.contains("Explore depth"))
    }
}
