import XCTest
@testable import FocusSpace

final class PersistenceAccessibilityTests: XCTestCase {
    func testRepositoryRecoversLastValidCopyWhenPrimaryIsCorrupt() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = JSONFocusMapRepository(fileURL: folder.appending(path: "map.json"))
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let first = FocusMap(title: "Recovery point", nodes: [FocusNode(title: "Safe thought", createdAt: timestamp, updatedAt: timestamp)])
        let second = FocusMap(title: "Current", nodes: [FocusNode(title: "Latest thought", createdAt: timestamp, updatedAt: timestamp)])
        try repository.save(first)
        try repository.save(second)
        try Data("not json".utf8).write(to: repository.fileURL, options: .atomic)

        let outcome = try repository.loadRecovering()

        XCTAssertEqual(outcome.source, .recovery)
        XCTAssertEqual(outcome.map, first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.recoveryURL.path))
    }

    func testRepositoryRecoversWhenPrimaryWasRemoved() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = JSONFocusMapRepository(fileURL: folder.appending(path: "map.json"))
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let recovery = FocusMap(nodes: [FocusNode(title: "Recover me", createdAt: timestamp, updatedAt: timestamp)])
        try repository.save(recovery)
        try repository.save(FocusMap(nodes: []))
        try FileManager.default.removeItem(at: repository.fileURL)

        let outcome = try repository.loadRecovering()

        XCTAssertEqual(outcome.source, .recovery)
        XCTAssertEqual(outcome.map, recovery)
    }

    @MainActor
    func testStoreReportsRecoveryAndAutosavesAnAtomicChange() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = JSONFocusMapRepository(fileURL: folder.appending(path: "map.json"))
        let node = FocusNode(title: "Before")
        let recovery = FocusMap(title: "Recovered", nodes: [node])
        try repository.save(recovery)
        try repository.save(FocusMap(title: "Later", nodes: [node]))
        try Data("broken".utf8).write(to: repository.fileURL, options: .atomic)
        let store = FocusSpaceStore(repository: repository, autosaveDelay: .milliseconds(5))

        XCTAssertTrue(store.recoveredFromBackup)
        XCTAssertEqual(store.map.title, "Recovered")
        store.rename(node.id, to: "After autosave")
        await store.flushAutosave()

        let saved = try XCTUnwrap(repository.load())
        XCTAssertEqual(saved.nodes.first?.title, "After autosave")
        XCTAssertNotNil(store.lastSavedAt)
    }

    @MainActor
    func testImportExportRoundTripReplacesAndImmediatelySavesTheSpace() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = JSONFocusMapRepository(fileURL: folder.appending(path: "map.json"))
        try repository.save(FocusMap(title: "Original", nodes: []))
        let store = FocusSpaceStore(repository: repository)
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let imported = FocusMap(
            title: "Imported",
            nodes: [FocusNode(
                title: "Preserved",
                notes: "Imported context",
                kind: .reference,
                createdAt: timestamp,
                updatedAt: timestamp
            )]
        )

        try store.importMapData(FocusMapJSONCodec.encode(imported))

        XCTAssertEqual(store.map, imported)
        XCTAssertEqual(try repository.load(), imported)
        XCTAssertEqual(try FocusMapJSONCodec.decode(store.exportMapData()), imported)
    }

    func testAccessibilityDescriptionIncludesDepthHierarchyLinksAndUrgency() throws {
        let parent = FocusNode(title: "Programme", kind: .project)
        let related = FocusNode(title: "Evidence", kind: .reference)
        let child = FocusNode(
            title: "Review",
            kind: .task,
            attention: 0.74,
            parentID: parent.id,
            relatedNodeIDs: [related.id],
            urgency: .overdue
        )
        let map = FocusMap(nodes: [parent, child, related])
        let item = FocusSceneSnapshot.Item(
            id: child.id,
            title: child.title,
            kind: child.kind,
            position: child.position,
            attention: child.attention,
            parentID: child.parentID,
            hierarchyDepth: 1,
            urgency: child.urgency,
            isEnabled: true,
            isSelected: false,
            isDimmed: false
        )

        let descriptor = FocusAccessibilityDescriptor.node(item, in: map)

        XCTAssertEqual(descriptor.label, "Review")
        XCTAssertTrue(descriptor.value.contains("74 percent attention"))
        XCTAssertTrue(descriptor.value.contains("child of Programme"))
        XCTAssertTrue(descriptor.value.contains("related to Evidence"))
        XCTAssertTrue(descriptor.value.contains("overdue"))
    }

    @MainActor
    func testKeyboardTraversalAndManipulationPreserveSemanticDepth() throws {
        let parent = FocusNode(title: "Parent", position: SpatialPoint(x: 0, y: 2), attention: 0.6)
        let child = FocusNode(title: "Child", position: SpatialPoint(x: 0, y: 0), attention: 0.4, parentID: parent.id)
        let peer = FocusNode(title: "Peer", position: SpatialPoint(x: 2, y: 1), attention: 0.5)
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = JSONFocusMapRepository(fileURL: folder.appending(path: "map.json"))
        try repository.save(FocusMap(nodes: [parent, child, peer]))
        let store = FocusSpaceStore(repository: repository)

        store.selectNextThought()
        XCTAssertEqual(store.selection, parent.id)
        store.selectFirstChildThought()
        XCTAssertEqual(store.selection, child.id)
        store.selectParentThought()
        XCTAssertEqual(store.selection, parent.id)
        store.moveSelection(horizontal: 0.25, vertical: -0.25)
        XCTAssertEqual(store.map.node(id: parent.id)?.position, SpatialPoint(x: 0.25, y: 1.75))
        XCTAssertEqual(store.map.node(id: parent.id)?.attention, 0.6)
    }

    func testRendererFallbackActivatesForPreferenceArgumentOrMissingEffects() {
        XCTAssertFalse(WorkspaceRendererAvailability.usesListFallback(
            preference: false,
            arguments: [],
            supportsAdvancedEffects: true
        ))
        XCTAssertTrue(WorkspaceRendererAvailability.usesListFallback(
            preference: true,
            arguments: [],
            supportsAdvancedEffects: true
        ))
        XCTAssertTrue(WorkspaceRendererAvailability.usesListFallback(
            preference: false,
            arguments: ["FocusSpace", "--accessible-list"],
            supportsAdvancedEffects: true
        ))
        XCTAssertTrue(WorkspaceRendererAvailability.usesListFallback(
            preference: false,
            arguments: [],
            supportsAdvancedEffects: false
        ))
    }
}
