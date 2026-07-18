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
