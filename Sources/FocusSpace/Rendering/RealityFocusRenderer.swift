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
    private var nodeMeshes: [FocusNodeKind: MeshResource] = [:]
    private var frameMeshes: [String: MeshResource] = [:]
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
        let style = NodeVisualStyle.resolve(
            kind: .task,
            attention: 0.5,
            hierarchyDepth: 0,
            urgency: .none,
            isEnabled: true
        )
        let mesh = mesh(for: .task, style: style)
        let entity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
        entity.name = name
        entity.components.set(InputTargetComponent())
        entity.generateCollisionShapes(recursive: false)
        return entity
    }

    private func update(entity: Entity, for item: FocusSceneSnapshot.Item) {
        let style = NodeVisualStyle.resolve(
            kind: item.kind,
            attention: item.attention,
            hierarchyDepth: item.hierarchyDepth,
            urgency: item.urgency,
            isEnabled: item.isEnabled
        )
        entity.position = position(for: item)
        entity.components.set(OpacityComponent(opacity: item.isDimmed ? 0.06 : style.opacity))
        let depthScale = Float(0.78 + item.attention * 0.24)
        entity.scale = SIMD3<Float>(repeating: depthScale)

        guard let model = entity as? ModelEntity else { return }
        model.model?.mesh = mesh(for: item.kind, style: style)
        model.generateCollisionShapes(recursive: false)
        let color = style.color.nsColor.withSaturation(CGFloat(style.saturation))
        model.model?.materials = [
            PhysicallyBasedMaterial.focusSpace(
                color: color,
                attention: Float(item.attention),
                emissiveIntensity: style.emissiveIntensity,
                tokens: tokens
            )
        ]
        updateDecorations(on: model, item: item, style: style)
    }

    private func mesh(for kind: FocusNodeKind, style: NodeVisualStyle) -> MeshResource {
        if let cached = nodeMeshes[kind] { return cached }
        let mesh = MeshResource.generateBox(
            width: style.width,
            height: style.height,
            depth: 0.15,
            cornerRadius: style.cornerRadius
        )
        nodeMeshes[kind] = mesh
        return mesh
    }

    private func updateDecorations(
        on entity: ModelEntity,
        item: FocusSceneSnapshot.Item,
        style: NodeVisualStyle
    ) {
        let singleLineLimit = switch item.kind {
        case .project, .group: 15
        case .task, .reference: 12
        case .someday: 14
        }
        let title = NodeLabelLayout.displayTitle(item.title, singleLineLimit: singleLineLimit)
        let attentionBand = Int(item.attention * 20)
        let decorationName = "decorations-\(item.kind.rawValue)-\(item.urgency.rawValue)-\(item.isEnabled)-\(item.isSelected)-\(attentionBand)-\(title)"
        if entity.children.contains(where: { $0.name == decorationName }) { return }
        for child in entity.children where child.name.hasPrefix("decorations-") { child.removeFromParent() }

        let decorations = Entity()
        decorations.name = decorationName
        decorations.addChild(makeFrame(
            width: style.width,
            height: style.height,
            thickness: item.kind == .project ? 0.018 : 0.011,
            color: style.color.nsColor,
            opacity: style.borderOpacity,
            name: "kind-frame"
        ))

        let renderedTitle = title.contains("\n") ? title : "\n\(title)"
        let font = NSFont.systemFont(ofSize: 0.13, weight: item.isSelected ? .semibold : .medium)
        let mesh = MeshResource.generateText(
            renderedTitle,
            extrusionDepth: 0.002,
            font: font,
            containerFrame: CGRect(x: 0, y: 0, width: CGFloat(style.width - 0.34), height: CGFloat(style.height - 0.12)),
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        let labelAlpha = item.isDimmed ? 0.2 : 0.76 + item.attention * 0.24
        let material = UnlitMaterial(color: NSColor(white: 0.98, alpha: labelAlpha))
        let label = ModelEntity(mesh: mesh, materials: [material])
        label.name = "node-label"
        label.position = SIMD3<Float>(
            -style.width / 2 + 0.24,
            -style.height / 2 + 0.05,
            0.083
        )
        decorations.addChild(label)

        let glyph = makeGlyph(
            style.glyph,
            size: 0.12,
            color: NSColor(white: 1, alpha: 0.9),
            name: "kind-glyph"
        )
        glyph.position = SIMD3<Float>(-style.width / 2 + 0.09, -0.045, 0.087)
        decorations.addChild(glyph)

        if let urgencyGlyph = style.urgencyGlyph,
           let urgencyColor = style.urgencyColor {
            let badge = ModelEntity(
                mesh: .generateSphere(radius: 0.075),
                materials: [UnlitMaterial(color: urgencyColor.nsColor)]
            )
            badge.name = "urgency-badge"
            badge.position = SIMD3<Float>(style.width / 2 - 0.02, -style.height / 2 + 0.04, 0.11)
            let mark = makeGlyph(urgencyGlyph, size: 0.095, color: .white, name: "urgency-mark")
            mark.position = SIMD3<Float>(-0.025, -0.04, 0.076)
            badge.addChild(mark)
            decorations.addChild(badge)
        }

        if item.isSelected {
            let halo = makeFrame(
                width: style.width + 0.13,
                height: style.height + 0.13,
                thickness: 0.018,
                color: tokens.focusCore.nsColor,
                opacity: 0.68,
                name: "selection-halo"
            )
            halo.position.z = -0.012
            decorations.addChild(halo)
        }

        if !item.isEnabled {
            let slash = ModelEntity(
                mesh: .generateBox(width: style.width * 0.82, height: 0.016, depth: 0.007),
                materials: [UnlitMaterial(color: NSColor(white: 0.86, alpha: 0.32))]
            )
            slash.name = "disabled-mark"
            slash.orientation = simd_quatf(angle: -0.32, axis: SIMD3<Float>(0, 0, 1))
            slash.position.z = 0.092
            decorations.addChild(slash)
        }
        entity.addChild(decorations)
    }

    private func makeGlyph(
        _ glyph: String,
        size: CGFloat,
        color: NSColor,
        name: String
    ) -> ModelEntity {
        let mesh = MeshResource.generateText(
            glyph,
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: size, weight: .semibold)
        )
        let entity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
        entity.name = name
        return entity
    }

    private func makeFrame(
        width: Float,
        height: Float,
        thickness: Float,
        color: NSColor,
        opacity: Float,
        name: String
    ) -> Entity {
        let meshKey = "\(width)-\(height)-\(thickness)"
        let mesh: MeshResource
        if let cached = frameMeshes[meshKey] {
            mesh = cached
        } else if let generated = try? makeFrameMesh(width: width, height: height, thickness: thickness) {
            frameMeshes[meshKey] = generated
            mesh = generated
        } else {
            return Entity()
        }
        var material = UnlitMaterial(color: color)
        material.faceCulling = .none
        material.blending = .transparent(opacity: .init(scale: opacity))
        let frame = ModelEntity(mesh: mesh, materials: [material])
        frame.name = name
        return frame
    }

    private func makeFrameMesh(width: Float, height: Float, thickness: Float) throws -> MeshResource {
        let outerX = width / 2 + thickness / 2
        let outerY = height / 2 + thickness / 2
        let innerX = max(width / 2 - thickness / 2, 0)
        let innerY = max(height / 2 - thickness / 2, 0)
        let z: Float = 0.081
        let positions: [SIMD3<Float>] = [
            SIMD3<Float>(-outerX, outerY, z), SIMD3<Float>(outerX, outerY, z),
            SIMD3<Float>(outerX, -outerY, z), SIMD3<Float>(-outerX, -outerY, z),
            SIMD3<Float>(-innerX, innerY, z), SIMD3<Float>(innerX, innerY, z),
            SIMD3<Float>(innerX, -innerY, z), SIMD3<Float>(-innerX, -innerY, z)
        ]
        let indices: [UInt32] = [
            0, 1, 4, 4, 1, 5,
            1, 2, 5, 5, 2, 6,
            2, 3, 6, 6, 3, 7,
            3, 0, 7, 7, 0, 4
        ]
        var descriptor = MeshDescriptor(name: "node-frame")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
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
            Float(item.position.y) + NodeVisualStyle.resolve(
                kind: item.kind,
                attention: item.attention,
                hierarchyDepth: item.hierarchyDepth,
                urgency: item.urgency,
                isEnabled: item.isEnabled
            ).hierarchyOffset,
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
        emissiveIntensity: Float,
        tokens: FocusVisualTokens
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(scale: 0.2 + (1 - attention) * 0.22)
        material.metallic = 0.12
        material.emissiveColor = .init(
            color: color.withAlphaComponent(CGFloat(0.24 + attention * 0.42))
        )
        material.emissiveIntensity = emissiveIntensity
        return material
    }
}

private extension NSColor {
    func withSaturation(_ multiplier: CGFloat) -> NSColor {
        guard let rgb = usingColorSpace(.deviceRGB) else { return self }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(
            hue: hue,
            saturation: min(max(saturation * multiplier, 0), 1),
            brightness: brightness,
            alpha: alpha
        )
    }
}
