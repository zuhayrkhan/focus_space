import RealityKit
import XCTest
@testable import FocusSpace

final class ExperienceFoundationTests: XCTestCase {
    func testDemoScenesAreDeterministicAndInternallyValid() {
        for scene in DemoScene.allCases {
            XCTAssertEqual(DemoScene(slug: scene.slug), scene)
            let first = scene.map
            let second = scene.map
            XCTAssertEqual(first, second, "\(scene.rawValue) must be deterministic")

            let ids = Set(first.nodes.map(\.id))
            XCTAssertEqual(ids.count, first.nodes.count)
            for node in first.nodes {
                if let parentID = node.parentID {
                    XCTAssertTrue(ids.contains(parentID), "\(node.title) has a missing parent")
                }
            }
        }
        let northStar = DemoScene.northStar.map.nodes
        XCTAssertEqual(Set(northStar.map(\.kind)), Set(FocusNodeKind.allCases))
        XCTAssertTrue(northStar.contains { $0.urgency == .overdue })
        XCTAssertTrue(northStar.contains { !$0.isEnabled })
    }

    func testVisualLanguageUsesShapeGlyphAndIntensityAsWellAsColour() {
        let styles = FocusNodeKind.allCases.map {
            NodeVisualStyle.resolve(
                kind: $0,
                attention: 0.7,
                hierarchyDepth: 0,
                urgency: .none,
                isEnabled: true
            )
        }

        XCTAssertEqual(Set(styles.map(\.silhouette)).count, FocusNodeKind.allCases.count)
        XCTAssertEqual(Set(styles.map(\.glyph)).count, FocusNodeKind.allCases.count)
        XCTAssertGreaterThan(Set(styles.map { "\($0.width)x\($0.height)" }).count, 2)

        let near = NodeVisualStyle.resolve(kind: .task, attention: 0.95, hierarchyDepth: 0, urgency: .none, isEnabled: true)
        let far = NodeVisualStyle.resolve(kind: .task, attention: 0.1, hierarchyDepth: 0, urgency: .none, isEnabled: true)
        XCTAssertGreaterThan(near.opacity, far.opacity)
        XCTAssertGreaterThan(near.saturation, far.saturation)
        XCTAssertGreaterThan(near.borderOpacity, far.borderOpacity)
        XCTAssertGreaterThan(near.emissiveIntensity, far.emissiveIntensity)

        let disabled = NodeVisualStyle.resolve(kind: .task, attention: 0.95, hierarchyDepth: 0, urgency: .none, isEnabled: false)
        XCTAssertEqual(disabled.glyph, "—")
        XCTAssertLessThan(disabled.opacity, near.opacity)
        XCTAssertLessThan(disabled.saturation, near.saturation)

        let overdue = NodeVisualStyle.resolve(kind: .task, attention: 0.7, hierarchyDepth: 2, urgency: .overdue, isEnabled: true)
        XCTAssertEqual(overdue.urgencyGlyph, "!")
        XCTAssertLessThan(overdue.hierarchyOffset, near.hierarchyOffset)
    }

    func testLabelLayoutPreservesShortAndMultilingualTextAndTruncatesLongText() {
        XCTAssertEqual(NodeLabelLayout.displayTitle("Ship it"), "Ship it")
        XCTAssertEqual(NodeLabelLayout.displayTitle("Release Focus Space"), "Release\nFocus Space")
        XCTAssertEqual(
            NodeLabelLayout.displayTitle("Keyboard flow", singleLineLimit: 12),
            "Keyboard\nflow"
        )
        XCTAssertTrue(NodeLabelLayout.displayTitle("競合分析 / Competitor analysis").contains("競合分析"))
        XCTAssertTrue(NodeLabelLayout.displayTitle("مراجعة تجربة المستخدم").contains("مراجعة"))

        let long = NodeLabelLayout.displayTitle("Audit preparation and evidence review across every jurisdiction")
        XCTAssertTrue(long.contains("\n"))
        XCTAssertTrue(long.hasSuffix("…"))
        XCTAssertLessThanOrEqual(long.filter { $0 != "\n" }.count, 38)
    }

    func testQualityRecommendationDegradesForPowerAndMemory() {
        XCTAssertEqual(
            SceneQualityProfile.recommended(isLowPowerModeEnabled: true, physicalMemory: 64_000_000_000),
            .efficient
        )
        XCTAssertEqual(
            SceneQualityProfile.recommended(isLowPowerModeEnabled: false, physicalMemory: 4_000_000_000),
            .efficient
        )
        XCTAssertEqual(
            SceneQualityProfile.recommended(isLowPowerModeEnabled: false, physicalMemory: 16_000_000_000),
            .balanced
        )
        XCTAssertEqual(
            SceneQualityProfile.recommended(isLowPowerModeEnabled: false, physicalMemory: 32_000_000_000),
            .cinematic
        )
    }

    func testQualityProfilesIncreaseDetailMonotonically() {
        XCTAssertLessThan(SceneQualityProfile.efficient.starCount, SceneQualityProfile.balanced.starCount)
        XCTAssertLessThan(SceneQualityProfile.balanced.starCount, SceneQualityProfile.cinematic.starCount)
        XCTAssertLessThan(SceneQualityProfile.efficient.guideSegmentCount, SceneQualityProfile.balanced.guideSegmentCount)
        XCTAssertLessThan(SceneQualityProfile.balanced.guideSegmentCount, SceneQualityProfile.cinematic.guideSegmentCount)
    }

    @MainActor
    func testRendererCreatesAtmosphericSceneAndHonoursReduceMotion() throws {
        let renderer = RealityFocusRenderer(quality: .efficient)
        let root = renderer.makeScene()
        XCTAssertNotNil(root.findEntity(named: RealityFocusRenderer.atmosphereName))

        renderer.updateAmbient(root: root, reduceMotion: false)
        XCTAssertFalse(renderer.isAmbientMotionPaused)

        renderer.updateAmbient(root: root, reduceMotion: true)
        XCTAssertTrue(renderer.isAmbientMotionPaused)
        XCTAssertNotNil(root.findEntity(named: "focus-origin"))
        XCTAssertNotNil(root.findEntity(named: "orbital-guides"))
        XCTAssertNotNil(root.findEntity(named: "cool-stars"))
    }

    @MainActor
    func testRendererUsesHaloWithoutChangingSelectedNodeScale() throws {
        let renderer = RealityFocusRenderer(quality: .efficient)
        let root = renderer.makeScene()
        let id = UUID()
        let base = FocusSceneSnapshot.Item(
            id: id,
            title: "Selected node",
            kind: .group,
            position: .zero,
            attention: 0.8,
            parentID: nil,
            hierarchyDepth: 0,
            urgency: .soon,
            isEnabled: true,
            isSelected: false,
            isDimmed: false
        )
        renderer.reconcile(root: root, snapshot: FocusSceneSnapshot(items: [base]))
        let entity = try XCTUnwrap(root.findEntity(named: "node-\(id.uuidString)"))
        let unselectedScale = entity.scale

        let selected = FocusSceneSnapshot.Item(
            id: id,
            title: base.title,
            kind: base.kind,
            position: base.position,
            attention: base.attention,
            parentID: nil,
            hierarchyDepth: 0,
            urgency: base.urgency,
            isEnabled: true,
            isSelected: true,
            isDimmed: false
        )
        renderer.reconcile(root: root, snapshot: FocusSceneSnapshot(items: [selected]))

        XCTAssertEqual(entity.scale, unselectedScale)
        XCTAssertNotNil(entity.findEntity(named: "selection-halo"))
        XCTAssertNotNil(entity.findEntity(named: "kind-glyph"))
        XCTAssertNotNil(entity.findEntity(named: "urgency-badge"))
    }

    @MainActor
    func testRendererReconcilesEveryDeterministicFixture() throws {
        for scene in DemoScene.allCases {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            let store = FocusSpaceStore(repository: JSONFocusMapRepository(fileURL: folder.appending(path: "map.json")))
            store.preview(scene)
            store.filter = .all
            let renderer = RealityFocusRenderer(quality: .efficient)
            let root = renderer.makeScene()

            renderer.reconcile(root: root, snapshot: store.sceneSnapshot)

            let renderedNodeCount = root.children.filter { $0.name.hasPrefix("node-") }.count
            XCTAssertEqual(renderedNodeCount, scene.map.nodes.count, scene.rawValue)
            for node in scene.map.nodes {
                XCTAssertNotNil(root.findEntity(named: "node-\(node.id.uuidString)"), node.title)
            }
        }
    }

    @MainActor
    func testStoreCarriesHierarchyAndEditableVisualStatesIntoSnapshot() throws {
        let parent = FocusNode(title: "Parent", kind: .project)
        let child = FocusNode(title: "Child", kind: .group, parentID: parent.id)
        let grandchild = FocusNode(title: "Grandchild", parentID: child.id)
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = JSONFocusMapRepository(fileURL: folder.appending(path: "map.json"))
        try repository.save(FocusMap(nodes: [parent, child, grandchild]))
        let store = FocusSpaceStore(repository: repository)
        store.filter = .all

        store.setKind(grandchild.id, to: .reference)
        store.setUrgency(grandchild.id, to: .overdue)
        store.setEnabled(grandchild.id, to: false)

        let item = try XCTUnwrap(store.sceneSnapshot.items.first { $0.id == grandchild.id })
        XCTAssertEqual(item.hierarchyDepth, 2)
        XCTAssertEqual(item.kind, .reference)
        XCTAssertEqual(item.urgency, .overdue)
        XCTAssertFalse(item.isEnabled)
        XCTAssertTrue(store.canUndo)
    }

    @MainActor
    func testDemoPreviewRestoresPersonalMapWithoutPersistingDemoChanges() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = JSONFocusMapRepository(fileURL: folder.appending(path: "map.json"))
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let personal = FocusMap(
            title: "Personal",
            nodes: [FocusNode(title: "Private thought", createdAt: timestamp, updatedAt: timestamp)]
        )
        try repository.save(personal)
        let store = FocusSpaceStore(repository: repository)

        store.preview(.northStar)
        XCTAssertEqual(store.demoScene, .northStar)
        XCTAssertNotEqual(store.map, personal)

        store.preview(nil)
        XCTAssertNil(store.demoScene)
        XCTAssertEqual(store.map, personal)
        XCTAssertEqual(try repository.load(), personal)
    }
}
