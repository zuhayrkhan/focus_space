import RealityKit
import SwiftUI

@MainActor
final class RealityFocusRenderer {
    static let rootName = "focus-space-root"
    static let atmosphereName = "atmosphere-root"

    let quality: SceneQualityProfile
    let tokens: FocusVisualTokens
    private var lastSnapshot: FocusSceneSnapshot?
    private var ambientController: AnimationPlaybackController?
    private(set) var isAmbientMotionPaused = false

    init(
        quality: SceneQualityProfile = .recommended,
        tokens: FocusVisualTokens = .midnight
    ) {
        self.quality = quality
        self.tokens = tokens
    }

    func makeScene() -> Entity {
        let root = Entity()
        root.name = Self.rootName
        root.addChild(makeCamera())
        root.addChild(makeAtmosphere())
        root.addChild(makeFocusOrigin())
        addLighting(to: root)
        return root
    }

    func reconcile(root: Entity, snapshot: FocusSceneSnapshot) {
        guard lastSnapshot != snapshot else { return }
        lastSnapshot = snapshot

        let desiredIDs = Set(snapshot.items.map { $0.id.uuidString })
        for child in root.children where child.name.hasPrefix("node-") {
            let id = String(child.name.dropFirst(5))
            if !desiredIDs.contains(id) { child.removeFromParent() }
        }

        for item in snapshot.items {
            let name = "node-\(item.id.uuidString)"
            let entity = root.findEntity(named: name) ?? makeNode(name: name)
            if entity.parent == nil { root.addChild(entity) }
            update(entity: entity, for: item)
        }

        reconcileRelationships(root: root, snapshot: snapshot)
    }

    func updateAmbient(root: Entity, reduceMotion: Bool) {
        guard root.findEntity(named: Self.atmosphereName) != nil else { return }
        guard isAmbientMotionPaused != reduceMotion else { return }
        isAmbientMotionPaused = reduceMotion
        if reduceMotion {
            ambientController?.pause()
        } else {
            ambientController?.resume()
        }
    }

    private func makeCamera() -> PerspectiveCamera {
        let camera = PerspectiveCamera()
        camera.name = "focus-camera"
        camera.camera.fieldOfViewInDegrees = tokens.cameraFieldOfView
        camera.position = SIMD3<Float>(0, 0.05, tokens.cameraDistance)
        return camera
    }

    private func makeAtmosphere() -> Entity {
        let atmosphere = Entity()
        atmosphere.name = Self.atmosphereName

        if let coolStars = try? makeStarField(
            name: "cool-stars",
            count: Int(Double(quality.starCount) * 0.76),
            seed: 0xF0C05ACE,
            color: tokens.starlight.nsColor
        ) {
            atmosphere.addChild(coolStars)
        }
        if let warmStars = try? makeStarField(
            name: "warm-stars",
            count: max(8, Int(Double(quality.starCount) * 0.24)),
            seed: 0xC0FFEE,
            color: tokens.warmDust.nsColor
        ) {
            atmosphere.addChild(warmStars)
        }
        if let guides = try? makeOrbitalGuides() { atmosphere.addChild(guides) }
        let orbit = OrbitAnimation(
            name: "ambient-orbit",
            duration: tokens.ambientRevolutionSeconds,
            axis: SIMD3<Float>(0, 0, 1),
            spinClockwise: false,
            orientToPath: false,
            rotationCount: 1,
            repeatMode: .repeat
        )
        if let animation = try? AnimationResource.generate(with: orbit) {
            ambientController = atmosphere.playAnimation(animation)
        }
        return atmosphere
    }

    private func makeFocusOrigin() -> Entity {
        let origin = Entity()
        origin.name = "focus-origin"
        origin.position = SIMD3<Float>(0, 2.62, -0.35)

        if let halo = try? makeRing(
            name: "focus-halo",
            innerRadius: 0.105,
            outerRadius: 0.125,
            segments: 64,
            color: tokens.focusBlue.nsColor,
            opacity: 0.58
        ) {
            origin.addChild(halo)
        }
        if let outerHalo = try? makeRing(
            name: "focus-outer-halo",
            innerRadius: 0.205,
            outerRadius: 0.212,
            segments: 64,
            color: tokens.focusCore.nsColor,
            opacity: 0.18
        ) {
            outerHalo.scale = SIMD3<Float>(1.9, 0.72, 1)
            origin.addChild(outerHalo)
        }

        let core = ModelEntity(
            mesh: .generateSphere(radius: 0.065),
            materials: [UnlitMaterial(color: tokens.focusCore.nsColor)]
        )
        origin.addChild(core)

        let verticalRay = ModelEntity(
            mesh: .generateBox(width: 0.008, height: 3.7, depth: 0.006),
            materials: [UnlitMaterial(color: tokens.focusBlue.nsColor.withAlphaComponent(0.26))]
        )
        verticalRay.position.y = -1.88
        verticalRay.components.set(OpacityComponent(opacity: 0.32))
        origin.addChild(verticalRay)

        for angle in [-0.13 as Float, 0.13] {
            let ray = ModelEntity(
                mesh: .generateBox(width: 2.2, height: 0.006, depth: 0.004),
                materials: [UnlitMaterial(color: tokens.focusCore.nsColor.withAlphaComponent(0.08))]
            )
            ray.orientation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 0, 1))
            ray.components.set(OpacityComponent(opacity: 0.12))
            origin.addChild(ray)
        }

        let labelMesh = MeshResource.generateText(
            "FOCUS\nYOU ARE HERE",
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.085, weight: .semibold),
            containerFrame: CGRect(x: 0, y: 0, width: 1.1, height: 0.3),
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        let label = ModelEntity(
            mesh: labelMesh,
            materials: [UnlitMaterial(color: tokens.focusCore.nsColor)]
        )
        label.position = SIMD3<Float>(-0.55, 0.2, 0.02)
        label.components.set(OpacityComponent(opacity: 0.82))
        origin.addChild(label)

        let focusLight = PointLight()
        focusLight.light.color = tokens.focusCore.nsColor
        focusLight.light.intensity = 5_200
        focusLight.light.attenuationRadius = 7
        focusLight.position = SIMD3<Float>(0, 0, 0.6)
        origin.addChild(focusLight)
        return origin
    }

    private func addLighting(to root: Entity) {
        let key = DirectionalLight()
        key.name = "key-light"
        key.light.color = NSColor(red: 0.72, green: 0.84, blue: 1, alpha: 1)
        key.light.intensity = 1_800
        key.orientation = simd_quatf(angle: -.pi / 4, axis: SIMD3<Float>(1, 0.3, 0))
        root.addChild(key)

        let fill = PointLight()
        fill.name = "fill-light"
        fill.light.color = NSColor(red: 0.22, green: 0.42, blue: 1, alpha: 1)
        fill.light.intensity = 3_200
        fill.light.attenuationRadius = 13
        fill.position = SIMD3<Float>(-3.5, 1.7, 4.5)
        root.addChild(fill)
    }

    private func makeNode(name: String) -> ModelEntity {
        let mesh = MeshResource.generateBox(width: 1.42, height: 0.62, depth: 0.15, cornerRadius: 0.12)
        let entity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
        entity.name = name
        entity.components.set(InputTargetComponent())
        entity.generateCollisionShapes(recursive: false)
        return entity
    }

    private func update(entity: Entity, for item: FocusSceneSnapshot.Item) {
        entity.position = position(for: item)
        let distanceFade = Float(0.42 + item.attention * 0.58)
        entity.components.set(OpacityComponent(opacity: item.isDimmed ? 0.07 : distanceFade))
        let depthScale = Float(0.78 + item.attention * 0.24)
        let selectedScale: Float = item.isSelected ? 1.055 : 1
        entity.scale = SIMD3<Float>(repeating: depthScale * selectedScale)

        guard let model = entity as? ModelEntity else { return }
        let warmth = Float(item.attention)
        let color = NSColor(
            red: CGFloat(0.10 + warmth * 0.16),
            green: CGFloat(0.18 + warmth * 0.21),
            blue: CGFloat(0.36 + warmth * 0.52),
            alpha: 1
        )
        model.model?.materials = [
            PhysicallyBasedMaterial.focusSpace(
                color: color,
                attention: warmth,
                selected: item.isSelected,
                tokens: tokens
            )
        ]
        updateLabel(on: model, item: item)
    }

    private func updateLabel(on entity: ModelEntity, item: FocusSceneSnapshot.Item) {
        let labelName = "label-\(item.title)-\(item.isSelected)"
        if entity.children.contains(where: { $0.name == labelName }) { return }
        for child in entity.children where child.name.hasPrefix("label-") { child.removeFromParent() }

        let font = NSFont.systemFont(ofSize: 0.13, weight: item.isSelected ? .semibold : .medium)
        let mesh = MeshResource.generateText(
            item.title,
            extrusionDepth: 0.002,
            font: font,
            containerFrame: CGRect(x: 0, y: 0, width: 1.18, height: 0.4),
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        let labelAlpha = item.isDimmed ? 0.2 : 0.78 + item.attention * 0.22
        let material = UnlitMaterial(color: NSColor(white: 0.98, alpha: labelAlpha))
        let label = ModelEntity(mesh: mesh, materials: [material])
        label.name = labelName
        label.position = SIMD3<Float>(-0.59, -0.12, 0.079)
        entity.addChild(label)
    }

    private func reconcileRelationships(root: Entity, snapshot: FocusSceneSnapshot) {
        for child in root.children where child.name.hasPrefix("link-") { child.removeFromParent() }
        let visible = snapshot.items.filter { !$0.isDimmed }
        let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        for child in visible {
            guard let parentID = child.parentID, let parent = byID[parentID] else { continue }
            let start = position(for: parent)
            let end = position(for: child)
            let vector = end - start
            let length = simd_length(vector)
            guard length > 0.001 else { continue }
            let mesh = MeshResource.generateBox(width: length, height: 0.009, depth: 0.009)
            let averageAttention = (parent.attention + child.attention) / 2
            let material = UnlitMaterial(
                color: tokens.focusBlue.nsColor.withAlphaComponent(0.12 + averageAttention * 0.24)
            )
            let link = ModelEntity(mesh: mesh, materials: [material])
            link.name = "link-\(parentID)-\(child.id)"
            link.position = (start + end) / 2
            link.orientation = simd_quatf(from: SIMD3<Float>(1, 0, 0), to: vector / length)
            root.addChild(link)
        }
    }

    private func position(for item: FocusSceneSnapshot.Item) -> SIMD3<Float> {
        let range = tokens.attentionNearZ - tokens.attentionFarZ
        return SIMD3<Float>(
            Float(item.position.x),
            Float(item.position.y),
            tokens.attentionFarZ + Float(item.attention) * range
        )
    }

    private func makeStarField(
        name: String,
        count: Int,
        seed: UInt64,
        color: NSColor
    ) throws -> ModelEntity {
        var random = SeededRandom(seed: seed)
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(count * 4)
        indices.reserveCapacity(count * 6)

        for index in 0..<count {
            let x = random.float(in: -7.2...7.2)
            let y = random.float(in: -4.5...4.5)
            let z = random.float(in: -4.8 ... -3.05)
            let size = random.float(in: 0.0035...0.012)
            let base = UInt32(index * 4)
            positions.append(contentsOf: [
                SIMD3<Float>(x - size, y - size, z),
                SIMD3<Float>(x + size, y - size, z),
                SIMD3<Float>(x - size, y + size, z),
                SIMD3<Float>(x + size, y + size, z)
            ])
            indices.append(contentsOf: [base, base + 1, base + 2, base + 2, base + 1, base + 3])
        }

        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        let mesh = try MeshResource.generate(from: [descriptor])
        var material = UnlitMaterial(color: color.withAlphaComponent(1))
        material.blending = .transparent(opacity: name == "warm-stars" ? 0.48 : 0.52)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = name
        return entity
    }

    private func makeOrbitalGuides() throws -> ModelEntity {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let ringSizes: [(Float, Float)] = [(2.2, 0.68), (3.4, 1.16), (4.8, 1.72), (6.3, 2.35)]
        let segments = quality.guideSegmentCount
        let thickness: Float = quality == .efficient ? 0.008 : 0.011

        for (ringIndex, size) in ringSizes.enumerated() {
            for segment in 0..<segments {
                let startAngle = Float(segment) / Float(segments) * .pi * 2
                let endAngle = Float(segment + 1) / Float(segments) * .pi * 2
                let start = SIMD3<Float>(cos(startAngle) * size.0, sin(startAngle) * size.1 - 0.2, -2.98 - Float(ringIndex) * 0.05)
                let end = SIMD3<Float>(cos(endAngle) * size.0, sin(endAngle) * size.1 - 0.2, -2.98 - Float(ringIndex) * 0.05)
                appendLineQuad(from: start, to: end, thickness: thickness, positions: &positions, indices: &indices)
            }
        }

        for spoke in 0..<12 {
            let angle = Float(spoke) / 12 * .pi * 2
            let start = SIMD3<Float>(cos(angle) * 0.4, sin(angle) * 0.12 - 0.2, -3.16)
            let end = SIMD3<Float>(cos(angle) * 6.3, sin(angle) * 2.35 - 0.2, -3.16)
            appendLineQuad(from: start, to: end, thickness: thickness * 0.7, positions: &positions, indices: &indices)
        }

        var descriptor = MeshDescriptor(name: "orbital-guides")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        let mesh = try MeshResource.generate(from: [descriptor])
        var material = UnlitMaterial(color: tokens.focusBlue.nsColor)
        material.faceCulling = .none
        material.blending = .transparent(opacity: 0.12)
        let guides = ModelEntity(mesh: mesh, materials: [material])
        guides.name = "orbital-guides"
        return guides
    }

    private func makeRing(
        name: String,
        innerRadius: Float,
        outerRadius: Float,
        segments: Int,
        color: NSColor,
        opacity: Float
    ) throws -> ModelEntity {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(segments * 4)
        indices.reserveCapacity(segments * 6)

        for segment in 0..<segments {
            let startAngle = Float(segment) / Float(segments) * .pi * 2
            let endAngle = Float(segment + 1) / Float(segments) * .pi * 2
            let base = UInt32(positions.count)
            positions.append(contentsOf: [
                SIMD3<Float>(cos(startAngle) * innerRadius, sin(startAngle) * innerRadius, 0),
                SIMD3<Float>(cos(startAngle) * outerRadius, sin(startAngle) * outerRadius, 0),
                SIMD3<Float>(cos(endAngle) * innerRadius, sin(endAngle) * innerRadius, 0),
                SIMD3<Float>(cos(endAngle) * outerRadius, sin(endAngle) * outerRadius, 0)
            ])
            indices.append(contentsOf: [base, base + 1, base + 2, base + 2, base + 1, base + 3])
        }

        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        let mesh = try MeshResource.generate(from: [descriptor])
        var material = UnlitMaterial(color: color)
        material.faceCulling = .none
        material.blending = .transparent(opacity: .init(scale: opacity))
        let ring = ModelEntity(mesh: mesh, materials: [material])
        ring.name = name
        return ring
    }

    private func appendLineQuad(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        thickness: Float,
        positions: inout [SIMD3<Float>],
        indices: inout [UInt32]
    ) {
        let direction = end - start
        let length = max(simd_length(SIMD2<Float>(direction.x, direction.y)), 0.0001)
        let perpendicular = SIMD3<Float>(-direction.y / length, direction.x / length, 0) * thickness
        let base = UInt32(positions.count)
        positions.append(contentsOf: [start - perpendicular, start + perpendicular, end - perpendicular, end + perpendicular])
        indices.append(contentsOf: [base, base + 1, base + 2, base + 2, base + 1, base + 3])
    }
}

private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func float(in range: ClosedRange<Float>) -> Float {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let unit = Float(state >> 40) / Float(1 << 24)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}

private extension PhysicallyBasedMaterial {
    static func focusSpace(
        color: NSColor,
        attention: Float,
        selected: Bool,
        tokens: FocusVisualTokens
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(scale: 0.2 + (1 - attention) * 0.22)
        material.metallic = 0.12
        material.emissiveColor = .init(
            color: selected
                ? tokens.focusCore.nsColor
                : tokens.focusBlue.nsColor.withAlphaComponent(CGFloat(0.28 + attention * 0.38))
        )
        material.emissiveIntensity = selected ? 0.46 : 0.08 + attention * 0.18
        return material
    }
}
