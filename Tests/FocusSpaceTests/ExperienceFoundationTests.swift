import AppKit
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
        XCTAssertFalse(DemoScene.deepHierarchy.map.nodes.first?.notes.isEmpty ?? true)
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

    func testGlobalShapePreferenceCreatesAConsistentVisualLanguage() {
        for preference in [NodeShapePreference.rounded, .capsule, .compact] {
            let styles = FocusNodeKind.allCases.map {
                NodeVisualStyle.resolve(
                    kind: $0,
                    attention: 0.7,
                    hierarchyDepth: 0,
                    urgency: .none,
                    isEnabled: true,
                    shapePreference: preference
                )
            }
            XCTAssertEqual(Set(styles.map(\.silhouette)).count, 1)
            XCTAssertEqual(Set(styles.map(\.cornerRadius)).count, 1)
            XCTAssertEqual(Set(styles.map(\.width)).count, 1)
            XCTAssertEqual(Set(styles.map(\.height)).count, 1)
            XCTAssertEqual(Set(styles.map { "\($0.color.red)-\($0.color.green)-\($0.color.blue)" }).count, FocusNodeKind.allCases.count)
        }
    }

    func testNotesLayoutExpandsOnlyTheSelectedCard() {
        let normal = NodeVisualStyle.resolve(
            kind: .project, attention: 0.8, hierarchyDepth: 0,
            urgency: .none, isEnabled: true, isExpanded: false
        )
        let expanded = NodeVisualStyle.resolve(
            kind: .project, attention: 0.8, hierarchyDepth: 0,
            urgency: .none, isEnabled: true, isExpanded: true
        )
        XCTAssertGreaterThan(expanded.width, normal.width)
        XCTAssertGreaterThan(expanded.height, normal.height)
        XCTAssertTrue(NodeNotesLayout.displayText(String(repeating: "context ", count: 30)).hasSuffix("…"))
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
        XCTAssertNil(root.findEntity(named: "focus-origin"))
        XCTAssertNotNil(root.findEntity(named: "orbital-guides"))
        XCTAssertNotNil(root.findEntity(named: "cool-stars"))
    }

    @MainActor
    func testUniverseWebIsVolumetricAndItsOpacityIsAdjustable() throws {
        let renderer = RealityFocusRenderer(quality: .efficient)
        let root = renderer.makeScene()
        let guides = try XCTUnwrap(root.findEntity(named: "orbital-guides"))
        let bounds = guides.visualBounds(relativeTo: root)
        XCTAssertGreaterThan(bounds.extents.z, 3.2, "The web should occupy the universe's Z volume")

        renderer.updateGuideOpacity(root: root, opacity: 0.24)
        XCTAssertEqual(guides.components[OpacityComponent.self]?.opacity, 0.24)
        renderer.updateGuideOpacity(root: root, opacity: 9)
        XCTAssertEqual(guides.components[OpacityComponent.self]?.opacity, 0.3, "Opacity must remain visually bounded")
    }

    @MainActor
    func testUniverseWebAlwaysSitsBehindEveryNode() throws {
        let renderer = RealityFocusRenderer(quality: .efficient)
        let root = renderer.makeScene()
        let items = [
            FocusSceneSnapshot.Item(
                id: UUID(), title: "Parked", kind: .someday, position: .zero,
                attention: 0.08, parentID: nil, hierarchyDepth: 0, urgency: .none,
                isEnabled: true, isSelected: false, isDimmed: false
            ),
            FocusSceneSnapshot.Item(
                id: UUID(), title: "Now", kind: .project, position: .zero,
                attention: 0.96, parentID: nil, hierarchyDepth: 0, urgency: .none,
                isEnabled: true, isSelected: false, isDimmed: false
            )
        ]
        renderer.reconcile(root: root, snapshot: FocusSceneSnapshot(items: items))

        let guides = try XCTUnwrap(root.findEntity(named: "orbital-guides"))
        let guideBounds = guides.visualBounds(relativeTo: root)
        let forwardEdge = guideBounds.center.z + guideBounds.extents.z / 2
        let furthestNodeZ = FocusVisualTokens.midnight.attentionFarZ
            + Float(items.map(\.attention).min() ?? 0)
            * (FocusVisualTokens.midnight.attentionNearZ - FocusVisualTokens.midnight.attentionFarZ)
        XCTAssertLessThan(forwardEdge, furthestNodeZ)
    }

    @MainActor
    func testStarfieldFillsAWideBackgroundVolume() throws {
        let renderer = RealityFocusRenderer(quality: .efficient)
        let root = renderer.makeScene()
        let stars = try XCTUnwrap(root.findEntity(named: "cool-stars"))
        let bounds = stars.visualBounds(relativeTo: root)
        XCTAssertGreaterThan(bounds.extents.x, 20)
        XCTAssertGreaterThan(bounds.extents.y, 11)
        XCTAssertGreaterThan(bounds.extents.z, 4)
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
    func testRendererExpandsSelectedNodeToShowNotesAndHonoursShapePreference() throws {
        let renderer = RealityFocusRenderer(quality: .efficient)
        let root = renderer.makeScene()
        let id = UUID()
        let base = FocusSceneSnapshot.Item(
            id: id,
            title: "Programme",
            notes: "Bring the related work into one calm release.",
            kind: .project,
            position: .zero,
            attention: 0.8,
            parentID: nil,
            hierarchyDepth: 0,
            urgency: .none,
            isEnabled: true,
            isSelected: false,
            isDimmed: false
        )
        renderer.reconcile(root: root, snapshot: FocusSceneSnapshot(items: [base]), shapePreference: .capsule)
        let entity = try XCTUnwrap(root.findEntity(named: "node-\(id.uuidString)"))
        let normalBounds = entity.visualBounds(relativeTo: entity)
        XCTAssertNil(entity.findEntity(named: "node-notes"))

        let selected = FocusSceneSnapshot.Item(
            id: base.id,
            title: base.title,
            notes: base.notes,
            kind: base.kind,
            position: base.position,
            attention: base.attention,
            parentID: nil,
            hierarchyDepth: 0,
            urgency: .none,
            isEnabled: true,
            isSelected: true,
            isDimmed: false
        )
        renderer.reconcile(root: root, snapshot: FocusSceneSnapshot(items: [selected]), shapePreference: .capsule)
        let expandedBounds = entity.visualBounds(relativeTo: entity)
        XCTAssertGreaterThan(expandedBounds.extents.y, normalBounds.extents.y)
        XCTAssertNotNil(entity.findEntity(named: "node-notes"))
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

    func testRelationshipCurvesClipNodeBodiesAndDistinguishCrossLinks() {
        let source = SIMD3<Float>(0, 0, -1)
        let target = SIMD3<Float>(3, -2, 0.5)
        let hierarchy = RelationshipCurveGeometry.make(
            from: source,
            sourceSize: SIMD2<Float>(1.6, 0.7),
            to: target,
            targetSize: SIMD2<Float>(1.3, 0.5),
            kind: .hierarchy
        )
        let crossLink = RelationshipCurveGeometry.make(
            from: source,
            sourceSize: SIMD2<Float>(1.6, 0.7),
            to: target,
            targetSize: SIMD2<Float>(1.3, 0.5),
            kind: .crossLink
        )

        XCTAssertGreaterThan(simd_distance(hierarchy.points.first!, source), 0.2)
        XCTAssertGreaterThan(simd_distance(hierarchy.points.last!, target), 0.2)
        XCTAssertGreaterThan(crossLink.dashedSegments.count, 3)
        XCTAssertLessThan(crossLink.dashedSegments.count, crossLink.solidSegments.count)
        XCTAssertNotEqual(hierarchy.points[hierarchy.points.count / 2], crossLink.points[crossLink.points.count / 2])
        XCTAssertGreaterThan(hierarchy.points[hierarchy.points.count / 2].z, min(source.z, target.z))
    }

    @MainActor
    func testSelectionAndHoverCreateSemanticRelationshipContext() throws {
        let root = FocusNode(title: "Root", kind: .project)
        let branch = FocusNode(title: "Branch", kind: .group, parentID: root.id)
        let sibling = FocusNode(title: "Sibling", kind: .group, parentID: root.id)
        let leaf = FocusNode(title: "Leaf", parentID: branch.id, relatedNodeIDs: [sibling.id])
        let unrelated = FocusNode(title: "Unrelated")
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = JSONFocusMapRepository(fileURL: folder.appending(path: "map.json"))
        try repository.save(FocusMap(nodes: [root, branch, sibling, leaf, unrelated]))
        let store = FocusSpaceStore(repository: repository)
        store.filter = .all
        store.select(leaf.id)

        var snapshot = store.sceneSnapshot
        XCTAssertEqual(snapshot.items.first { $0.id == root.id }?.contextRole, .direct)
        XCTAssertEqual(snapshot.items.first { $0.id == sibling.id }?.contextRole, .subdued)
        XCTAssertEqual(snapshot.items.first { $0.id == unrelated.id }?.contextRole, .subdued)
        XCTAssertEqual(snapshot.relationships.filter { $0.kind == .crossLink }.count, 1)
        XCTAssertTrue(snapshot.relationships.contains { $0.targetID == leaf.id && $0.emphasis == .direct })

        store.hover(root.id)
        snapshot = store.sceneSnapshot
        XCTAssertEqual(snapshot.items.first { $0.id == sibling.id }?.contextRole, .branch)
        XCTAssertEqual(snapshot.items.first { $0.id == leaf.id }?.contextRole, .branch)
        store.hover(nil)
        XCTAssertEqual(store.sceneSnapshot.items.first { $0.id == root.id }?.contextRole, .direct)

        let selectedRelationshipCount = store.sceneSnapshot.relationships.count
        store.select(nil)
        snapshot = store.sceneSnapshot
        XCTAssertEqual(snapshot.relationships.count, selectedRelationshipCount)
        XCTAssertTrue(snapshot.relationships.allSatisfy { $0.emphasis == .standard })
        XCTAssertTrue(snapshot.items.allSatisfy { $0.contextRole == .none })
    }

    @MainActor
    func testRendererBuildsCurvedHierarchyAndDashedCrossLinkEntities() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = FocusSpaceStore(repository: JSONFocusMapRepository(fileURL: folder.appending(path: "map.json")))
        store.preview(.northStar)
        store.filter = .all
        let renderer = RealityFocusRenderer(quality: .efficient)
        let root = renderer.makeScene()
        renderer.reconcile(root: root, snapshot: store.sceneSnapshot)

        let links = root.children.filter { $0.name.hasPrefix("link-") }
        XCTAssertEqual(links.count, store.sceneSnapshot.relationships.count)
        XCTAssertTrue(links.contains { $0.findEntity(named: "hierarchy-core") != nil })
        XCTAssertTrue(links.contains { $0.findEntity(named: "cross-link-core") != nil })
        XCTAssertTrue(links.allSatisfy { $0.findEntity(named: "link-glow") != nil })
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
        store.setNotes(grandchild.id, to: "Evidence and context")

        let item = try XCTUnwrap(store.sceneSnapshot.items.first { $0.id == grandchild.id })
        XCTAssertEqual(item.hierarchyDepth, 2)
        XCTAssertEqual(item.kind, .reference)
        XCTAssertEqual(item.urgency, .overdue)
        XCTAssertEqual(item.notes, "Evidence and context")
        XCTAssertFalse(item.isEnabled)
        XCTAssertTrue(store.canUndo)
    }

    @MainActor
    func testArrangeMindMapSeparatesOverlapsPreservesDepthAndSupportsUndo() throws {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let root = FocusNode(title: "Root", kind: .project, position: .zero, attention: 0.2, createdAt: timestamp, updatedAt: timestamp)
        let first = FocusNode(title: "First", kind: .group, position: .zero, attention: 0.9, parentID: root.id, createdAt: timestamp, updatedAt: timestamp)
        let second = FocusNode(title: "Second", kind: .group, position: .zero, attention: 0.4, parentID: root.id, createdAt: timestamp, updatedAt: timestamp)
        let leaf = FocusNode(title: "Leaf", position: .zero, attention: 0.7, parentID: first.id, createdAt: timestamp, updatedAt: timestamp)
        let original = FocusMap(nodes: [root, first, second, leaf])
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = JSONFocusMapRepository(fileURL: folder.appending(path: "map.json"))
        try repository.save(original)
        let store = FocusSpaceStore(repository: repository)
        let attention = Dictionary(uniqueKeysWithValues: store.map.nodes.map { ($0.id, $0.attention) })

        store.arrangeMindMap()

        XCTAssertEqual(Set(store.map.nodes.map(\.position)).count, store.map.nodes.count)
        XCTAssertGreaterThan(store.map.node(id: root.id)!.position.y, store.map.node(id: first.id)!.position.y)
        XCTAssertGreaterThan(store.map.node(id: first.id)!.position.y, store.map.node(id: leaf.id)!.position.y)
        XCTAssertGreaterThan(abs(store.map.node(id: first.id)!.position.x - store.map.node(id: second.id)!.position.x), 1.6)
        XCTAssertTrue(store.map.nodes.allSatisfy { $0.attention == attention[$0.id] })
        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(store.cameraIntent.mode, .overview)
        XCTAssertGreaterThanOrEqual(store.cameraIntent.pose.distance, FocusCameraIntent.Pose.canonical.distance)

        store.undo()
        XCTAssertEqual(store.map, original)
    }

    func testArrangeMindMapUsesACompactGridForManyIndependentThoughts() {
        let nodes = (0..<20).map { FocusNode(title: "Thought \($0)", position: .zero) }
        let positions = MindMapArranger.positions(for: FocusMap(nodes: nodes))
        XCTAssertEqual(Set(positions.values).count, nodes.count)
        XCTAssertGreaterThan(Set(positions.values.map(\.y)).count, 2)
        XCTAssertLessThanOrEqual(positions.values.map { abs($0.x) }.max() ?? 0, 4.4)
    }

    func testCameraPoseAppliesSoftWorkspaceBounds() {
        let pose = FocusCameraIntent.Pose(
            target: SpatialPoint(x: 99, y: -99),
            targetAttention: 4,
            yaw: 180,
            pitch: -90,
            distance: 100
        ).bounded()
        XCTAssertEqual(pose.target.x, 6.5)
        XCTAssertEqual(pose.target.y, -4.2)
        XCTAssertEqual(pose.targetAttention, 1)
        XCTAssertEqual(pose.yaw, 55)
        XCTAssertEqual(pose.pitch, -34)
        XCTAssertEqual(pose.distance, 18)
    }

    @MainActor
    func testTrackpadMagnificationUsesOneStableGestureOriginInBothDirections() {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = FocusSpaceStore(repository: JSONFocusMapRepository(fileURL: folder.appending(path: "map.json")))
        var origin = FocusCameraIntent.Pose.canonical
        origin.distance = 10

        let stretched = store.zoomCameraPose(by: 1.25, from: origin)
        let pinched = store.zoomCameraPose(by: 0.8, from: origin)

        XCTAssertEqual(stretched.distance, 8, accuracy: 0.001)
        XCTAssertEqual(pinched.distance, 12.5, accuracy: 0.001)
        XCTAssertEqual(stretched.yaw, origin.yaw)
        XCTAssertEqual(stretched.pitch, origin.pitch)
        XCTAssertEqual(stretched.target, origin.target)
        XCTAssertEqual(TrackpadMagnificationBridge.scaleFactor(for: 0.25), 1.25)
        XCTAssertEqual(TrackpadMagnificationBridge.scaleFactor(for: -0.2), 0.8)
        XCTAssertEqual(TrackpadMagnificationBridge.scaleFactor(for: -9), 0.25)
    }

    @MainActor
    func testTrackpadMagnificationMonitorsTheNativeEventStreamForItsWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let attachment = MagnificationAttachmentView(frame: NSRect(x: 0, y: 0, width: 640, height: 600))
        window.contentView?.addSubview(attachment)

        let bridge = TrackpadMagnificationBridge(
            onBegan: {},
            onChanged: { _ in },
            onEnded: { _ in },
            onCancelled: {}
        )
        let coordinator = bridge.makeCoordinator()
        coordinator.attach(to: attachment)

        XCTAssertTrue(coordinator.isMonitoring)

        coordinator.detach()
        XCTAssertFalse(coordinator.isMonitoring)
    }

    @MainActor
    func testUniverseDragIsDirectResponsiveAndUsesBothAxes() {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = FocusSpaceStore(repository: JSONFocusMapRepository(fileURL: folder.appending(path: "map.json")))
        let origin = store.cameraIntent.pose

        store.orbitCamera(horizontal: 80, vertical: 60, from: origin)

        XCTAssertLessThan(store.cameraIntent.pose.yaw, -20)
        XCTAssertGreaterThan(store.cameraIntent.pose.pitch, 12)
        XCTAssertEqual(store.cameraIntent.mode, .free)
    }

    @MainActor
    func testTransientCameraPoseDoesNotPublishThroughSelectedInspectorState() {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = FocusSpaceStore(repository: JSONFocusMapRepository(fileURL: folder.appending(path: "map.json")))
        store.preview(.deepHierarchy)
        store.select(store.map.nodes[1].id)
        let intent = store.cameraIntent

        let preview = store.orbitCameraPose(horizontal: 70, vertical: -45, from: intent.pose)

        XCTAssertNotEqual(preview, intent.pose)
        XCTAssertEqual(store.cameraIntent, intent, "A live camera preview must not refresh the selected inspector")
    }

    @MainActor
    func testCameraNavigationDoesNotMutateAttentionAndFramesWholeBranch() throws {
        let root = FocusNode(title: "Root", position: SpatialPoint(x: -2, y: 1), attention: 0.2)
        let child = FocusNode(title: "Child", position: SpatialPoint(x: 3, y: -2), attention: 0.8, parentID: root.id)
        let unrelated = FocusNode(title: "Other", position: SpatialPoint(x: 6, y: 4), attention: 1)
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = JSONFocusMapRepository(fileURL: folder.appending(path: "map.json"))
        try repository.save(FocusMap(nodes: [root, child, unrelated]))
        let store = FocusSpaceStore(repository: repository)
        let originalMap = store.map

        store.orbitCamera(horizontal: 120, vertical: 50)
        store.zoomCamera(by: 1.4)
        store.panCamera(horizontal: 40, vertical: -30)
        XCTAssertEqual(store.map, originalMap)
        XCTAssertEqual(store.cameraIntent.mode, .free)
        let angleBeforeSelection = store.cameraIntent.pose

        store.select(root.id)
        XCTAssertEqual(store.cameraIntent.mode, .framed(root.id))
        XCTAssertEqual(store.cameraIntent.pose.target.x, -0.25, accuracy: 0.001)
        XCTAssertEqual(store.cameraIntent.pose.target.y, -0.05, accuracy: 0.001)
        XCTAssertEqual(store.cameraIntent.pose.targetAttention, 0.5, accuracy: 0.001)
        XCTAssertEqual(store.cameraIntent.pose.yaw, angleBeforeSelection.yaw, accuracy: 0.001)
        XCTAssertEqual(store.cameraIntent.pose.pitch, angleBeforeSelection.pitch, accuracy: 0.001)
        XCTAssertLessThan(store.cameraIntent.pose.distance, angleBeforeSelection.distance)
        XCTAssertEqual(store.map, originalMap)

        let framedBranch = store.cameraIntent
        store.select(root.id)
        XCTAssertEqual(store.cameraIntent, framedBranch, "Repeated selection should not keep zooming inward")
        store.select(child.id)
        XCTAssertEqual(store.cameraIntent, framedBranch, "A leaf selection should not move the camera")

        store.resetCamera()
        XCTAssertEqual(store.cameraIntent.mode, .canonical)
        XCTAssertEqual(store.cameraIntent.pose, .canonical)
    }

    @MainActor
    func testRendererConsumesCameraIntentIndependentlyFromSceneSnapshot() throws {
        let renderer = RealityFocusRenderer(quality: .efficient)
        let root = renderer.makeScene()
        let camera = try XCTUnwrap(root.findEntity(named: "focus-camera"))
        let originalPosition = camera.position
        let pose = FocusCameraIntent.Pose(
            target: SpatialPoint(x: 2, y: -1),
            targetAttention: 0.15,
            yaw: 22,
            pitch: -8,
            distance: 7
        )
        renderer.updateCamera(
            root: root,
            intent: FocusCameraIntent(pose: pose, mode: .free, revision: 1, isAnimated: false),
            reduceMotion: false
        )
        XCTAssertNotEqual(camera.position, originalPosition)
        XCTAssertEqual(camera.position, camera.position(relativeTo: root))
    }

    @MainActor
    func testRendererPreviewsNodeMotionImmediatelyAndKeepsUnchangedLinks() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = FocusSpaceStore(repository: JSONFocusMapRepository(fileURL: folder.appending(path: "map.json")))
        store.preview(.deepHierarchy)
        store.filter = .all
        let renderer = RealityFocusRenderer(quality: .efficient)
        let root = renderer.makeScene()
        let initial = store.sceneSnapshot
        renderer.reconcile(root: root, snapshot: initial)

        let movedNode = try XCTUnwrap(store.map.nodes.last)
        let movedEntity = try XCTUnwrap(root.findEntity(named: "node-\(movedNode.id.uuidString)"))
        let initialPosition = movedEntity.position
        let unrelatedRelationship = try XCTUnwrap(initial.relationships.first {
            $0.sourceID != movedNode.id && $0.targetID != movedNode.id
        })
        let unrelatedName = "link-\(unrelatedRelationship.kind.rawValue)-\(unrelatedRelationship.sourceID)-\(unrelatedRelationship.targetID)"
        let unrelatedLink = try XCTUnwrap(root.findEntity(named: unrelatedName))

        let originalMap = store.map
        let baseItem = try XCTUnwrap(initial.items.first { $0.id == movedNode.id })
        let movedPosition = SpatialPoint(x: movedNode.position.x + 1, y: movedNode.position.y - 0.5)
        let updatedItem = FocusSceneSnapshot.Item(
            id: baseItem.id,
            title: baseItem.title,
            kind: baseItem.kind,
            position: movedPosition,
            attention: baseItem.attention,
            parentID: baseItem.parentID,
            hierarchyDepth: baseItem.hierarchyDepth,
            urgency: baseItem.urgency,
            isEnabled: baseItem.isEnabled,
            isSelected: baseItem.isSelected,
            isDimmed: baseItem.isDimmed,
            isHovered: baseItem.isHovered,
            contextRole: baseItem.contextRole
        )
        renderer.previewNodeDrag(entity: movedEntity, item: updatedItem, snapshot: initial)
        XCTAssertNotEqual(movedEntity.position, initialPosition, "The active tile should move before reconciliation")
        XCTAssertEqual(store.map, originalMap, "A live tile preview must not refresh the selected inspector")

        store.move(movedNode.id, to: movedPosition)
        let updated = store.sceneSnapshot
        renderer.reconcile(root: root, snapshot: updated)
        XCTAssertTrue(root.findEntity(named: unrelatedName) === unrelatedLink, "Unchanged links should not be rebuilt during a drag")
        XCTAssertTrue(root.findEntity(named: "node-\(movedNode.id.uuidString)") === movedEntity)
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
