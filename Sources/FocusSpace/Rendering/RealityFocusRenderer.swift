import RealityKit
import SwiftUI

@MainActor
final class RealityFocusRenderer {
    static let rootName = "focus-space-root"
    static let atmosphereName = "atmosphere-root"

    let quality: SceneQualityProfile
    let tokens: FocusVisualTokens
    private var lastSnapshot: FocusSceneSnapshot?
    private var lastCameraRevision: Int?
    private weak var sceneRoot: Entity?
    private var ambientController: AnimationPlaybackController?
    private var nodeMeshes: [String: MeshResource] = [:]
    private var frameMeshes: [String: MeshResource] = [:]
    private var relationshipKeys: [String: RelationshipRenderKey] = [:]
    private var shapePreference: NodeShapePreference = .semantic
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
        sceneRoot = root
        root.addChild(makeCamera())
        root.addChild(makeAtmosphere())
        addLighting(to: root)
        return root
    }

    func reconcile(
        root: Entity,
        snapshot: FocusSceneSnapshot,
        shapePreference: NodeShapePreference = .semantic
    ) {
        let shapeChanged = self.shapePreference != shapePreference
        guard lastSnapshot != snapshot || shapeChanged else { return }
        self.shapePreference = shapePreference
        let previousItems = shapeChanged
            ? [:]
            : Dictionary(uniqueKeysWithValues: (lastSnapshot?.items ?? []).map { ($0.id, $0) })

        let desiredIDs = Set(snapshot.items.map { $0.id.uuidString })
        for child in root.children where child.name.hasPrefix("node-") {
            let id = String(child.name.dropFirst(5))
            if !desiredIDs.contains(id) { child.removeFromParent() }
        }

        for item in snapshot.items {
            let name = "node-\(item.id.uuidString)"
            let entity = root.findEntity(named: name) ?? makeNode(name: name)
            if entity.parent == nil { root.addChild(entity) }
            update(entity: entity, for: item, previous: previousItems[item.id])
        }

        reconcileRelationships(root: root, snapshot: snapshot)
        updateGuideDepth(root: root, snapshot: snapshot)
        lastSnapshot = snapshot
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

    func updateGuideOpacity(root: Entity, opacity: Double) {
        guard let guides = root.findEntity(named: "orbital-guides") else { return }
        let value = Float(min(max(opacity, 0), 0.3))
        guard guides.components[OpacityComponent.self]?.opacity != value else { return }
        guides.components.set(OpacityComponent(opacity: value))
    }

    func updateGuideDepth(root: Entity, snapshot: FocusSceneSnapshot) {
        guard let guides = root.findEntity(named: "orbital-guides") else { return }
        let nearestAllowedZ = snapshot.items
            .map { position(for: $0).z }
            .min()
            .map { $0 - 0.32 }
            ?? tokens.attentionFarZ - 0.32
        guard guides.position.z != nearestAllowedZ else { return }
        guides.position.z = nearestAllowedZ
    }

    func updateCamera(root: Entity, intent: FocusCameraIntent, reduceMotion: Bool) {
        guard lastCameraRevision != intent.revision else { return }
        lastCameraRevision = intent.revision
        applyCameraPose(root: root, pose: intent.pose, animated: intent.isAnimated, reduceMotion: reduceMotion)
    }

    private func applyCameraPose(
        root: Entity,
        pose: FocusCameraIntent.Pose,
        animated: Bool,
        reduceMotion: Bool
    ) {
        guard let camera = root.findEntity(named: "focus-camera") else { return }
        let range = Double(tokens.attentionNearZ - tokens.attentionFarZ)
        let target = SIMD3<Float>(
            Float(pose.target.x),
            Float(pose.target.y),
            tokens.attentionFarZ + Float(pose.targetAttention * range)
        )
        let yaw = Float(pose.yaw * .pi / 180)
        let pitch = Float(pose.pitch * .pi / 180)
        let distance = Float(pose.distance)
        let offset = SIMD3<Float>(
            sin(yaw) * cos(pitch) * distance,
            sin(pitch) * distance,
            cos(yaw) * cos(pitch) * distance
        )
        let position = target + offset
        let direction = simd_normalize(target - position)
        let orientation = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: direction)
        let transform = Transform(scale: .one, rotation: orientation, translation: position)
        camera.stopAllAnimations(recursive: false)
        if animated, !reduceMotion {
            camera.move(to: transform, relativeTo: root, duration: 0.58, timingFunction: .easeInOut)
        } else {
            camera.transform = transform
        }
    }

    func previewCamera(pose: FocusCameraIntent.Pose, reduceMotion: Bool) {
        guard let sceneRoot else { return }
        applyCameraPose(root: sceneRoot, pose: pose, animated: false, reduceMotion: reduceMotion)
    }

    func previewNodeDrag(
        entity: Entity,
        item: FocusSceneSnapshot.Item,
        snapshot: FocusSceneSnapshot
    ) {
        entity.position = position(for: item)
        let depthScale = Float(0.78 + item.attention * 0.24)
        entity.scale = SIMD3<Float>(repeating: depthScale)
        guard let sceneRoot else { return }
        let preview = FocusSceneSnapshot(
            items: snapshot.items.map { $0.id == item.id ? item : $0 },
            relationships: snapshot.relationships
        )
        reconcileRelationships(root: sceneRoot, snapshot: preview)
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
            isEnabled: true,
            shapePreference: shapePreference
        )
        let mesh = mesh(for: .task, style: style)
        let entity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
        entity.name = name
        entity.components.set(InputTargetComponent())
        entity.generateCollisionShapes(recursive: false)
        return entity
    }

    private func update(
        entity: Entity,
        for item: FocusSceneSnapshot.Item,
        previous: FocusSceneSnapshot.Item?
    ) {
        let style = NodeVisualStyle.resolve(
            kind: item.kind,
            attention: item.attention,
            hierarchyDepth: item.hierarchyDepth,
            urgency: item.urgency,
            isEnabled: item.isEnabled,
            shapePreference: shapePreference,
            isExpanded: item.isSelected && !item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        entity.position = position(for: item)
        guard needsVisualUpdate(from: previous, to: item) else { return }
        let contextOpacity: Float = switch item.contextRole {
        case .subdued: 0.50
        case .none, .branch, .direct: 1
        }
        entity.components.set(OpacityComponent(opacity: item.isDimmed ? 0.06 : style.opacity * contextOpacity))
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

    private func needsVisualUpdate(
        from previous: FocusSceneSnapshot.Item?,
        to item: FocusSceneSnapshot.Item
    ) -> Bool {
        guard let previous else { return true }
        return previous.title != item.title
            || previous.notes != item.notes
            || previous.kind != item.kind
            || previous.attention != item.attention
            || previous.hierarchyDepth != item.hierarchyDepth
            || previous.urgency != item.urgency
            || previous.isEnabled != item.isEnabled
            || previous.isSelected != item.isSelected
            || previous.isDimmed != item.isDimmed
            || previous.isHovered != item.isHovered
            || previous.contextRole != item.contextRole
    }

    private func mesh(for kind: FocusNodeKind, style: NodeVisualStyle) -> MeshResource {
        let key = "\(kind.rawValue)-\(style.silhouette)-\(style.width)-\(style.height)-\(style.cornerRadius)"
        if let cached = nodeMeshes[key] { return cached }
        let mesh = MeshResource.generateBox(
            width: style.width,
            height: style.height,
            depth: 0.15,
            cornerRadius: style.cornerRadius
        )
        nodeMeshes[key] = mesh
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
        let notes = NodeNotesLayout.displayText(item.notes)
        let showsNotes = item.isSelected && !notes.isEmpty
        let attentionBand = Int(item.attention * 20)
        let decorationName = "decorations-\(item.kind.rawValue)-\(item.urgency.rawValue)-\(item.isEnabled)-\(item.isSelected)-\(item.isHovered)-\(item.contextRole)-\(attentionBand)-\(title)-\(notes.hashValue)"
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

        let renderedTitle = showsNotes ? title : (title.contains("\n") ? title : "\n\(title)")
        let font = NSFont.systemFont(ofSize: 0.13, weight: item.isSelected ? .semibold : .medium)
        let mesh = MeshResource.generateText(
            renderedTitle,
            extrusionDepth: 0.002,
            font: font,
            containerFrame: CGRect(
                x: 0,
                y: 0,
                width: CGFloat(style.width - 0.34),
                height: CGFloat(showsNotes ? 0.32 : style.height - 0.12)
            ),
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        let labelAlpha = item.isDimmed ? 0.2 : 0.76 + item.attention * 0.24
        let material = UnlitMaterial(color: NSColor(white: 0.98, alpha: labelAlpha))
        let label = ModelEntity(mesh: mesh, materials: [material])
        label.name = "node-label"
        label.position = SIMD3<Float>(
            -style.width / 2 + 0.24,
            showsNotes ? style.height / 2 - 0.38 : -style.height / 2 + 0.05,
            0.083
        )
        decorations.addChild(label)

        if showsNotes {
            let divider = ModelEntity(
                mesh: .generateBox(width: style.width - 0.34, height: 0.006, depth: 0.004),
                materials: [UnlitMaterial(color: NSColor(white: 1, alpha: 0.18))]
            )
            divider.name = "notes-divider"
            divider.position = SIMD3<Float>(0, style.height / 2 - 0.47, 0.084)
            decorations.addChild(divider)

            let notesMesh = MeshResource.generateText(
                notes,
                extrusionDepth: 0.001,
                font: .systemFont(ofSize: 0.092, weight: .regular),
                containerFrame: CGRect(
                    x: 0,
                    y: 0,
                    width: CGFloat(style.width - 0.36),
                    height: CGFloat(style.height - 0.62)
                ),
                alignment: .left,
                lineBreakMode: .byWordWrapping
            )
            let notesLabel = ModelEntity(
                mesh: notesMesh,
                materials: [UnlitMaterial(color: NSColor(white: 0.92, alpha: 0.78))]
            )
            notesLabel.name = "node-notes"
            notesLabel.position = SIMD3<Float>(
                -style.width / 2 + 0.18,
                -style.height / 2 + 0.12,
                0.084
            )
            decorations.addChild(notesLabel)
        }

        let glyph = makeGlyph(
            style.glyph,
            size: 0.12,
            color: NSColor(white: 1, alpha: 0.9),
            name: "kind-glyph"
        )
        glyph.position = SIMD3<Float>(
            -style.width / 2 + 0.09,
            showsNotes ? style.height / 2 - 0.22 : -0.045,
            0.087
        )
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

        if item.isHovered || item.contextRole == .branch {
            let halo = makeFrame(
                width: style.width + (item.isHovered ? 0.18 : 0.08),
                height: style.height + (item.isHovered ? 0.18 : 0.08),
                thickness: item.isHovered ? 0.014 : 0.007,
                color: item.isHovered ? tokens.focusCore.nsColor : tokens.focusBlue.nsColor,
                opacity: item.isHovered ? 0.52 : 0.20,
                name: item.isHovered ? "hover-halo" : "family-halo"
            )
            halo.position.z = -0.018
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
        let byID = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })
        let desiredNames = Set(snapshot.relationships.map(relationshipName))
        for child in root.children where child.name.hasPrefix("link-") && !desiredNames.contains(child.name) {
            child.removeFromParent()
            relationshipKeys[child.name] = nil
        }
        for relationship in snapshot.relationships {
            guard let source = byID[relationship.sourceID], let target = byID[relationship.targetID] else { continue }
            let sourceStyle = visualStyle(for: source)
            let targetStyle = visualStyle(for: target)
            let name = relationshipName(relationship)
            let key = RelationshipRenderKey(
                relationship: relationship,
                sourcePosition: position(for: source),
                sourceSize: SIMD2<Float>(sourceStyle.width, sourceStyle.height),
                targetPosition: position(for: target),
                targetSize: SIMD2<Float>(targetStyle.width, targetStyle.height)
            )
            if relationshipKeys[name] == key, root.findEntity(named: name) != nil { continue }
            root.findEntity(named: name)?.removeFromParent()
            let curve = RelationshipCurveGeometry.make(
                from: key.sourcePosition,
                sourceSize: key.sourceSize,
                to: key.targetPosition,
                targetSize: key.targetSize,
                kind: relationship.kind,
                sampleCount: quality == .efficient ? 14 : 24
            )
            let segments = relationship.kind == .crossLink ? curve.dashedSegments : curve.solidSegments
            let link = Entity()
            link.name = name
            let opacity = relationshipOpacity(relationship)
            if let glow = try? makeRelationshipMesh(segments: segments, thickness: relationshipThickness(relationship) * 2.7) {
                var material = UnlitMaterial(color: relationshipColor(relationship))
                material.faceCulling = .none
                material.blending = .transparent(opacity: .init(scale: opacity * 0.20))
                let entity = ModelEntity(mesh: glow, materials: [material])
                entity.name = "link-glow"
                link.addChild(entity)
            }
            if let core = try? makeRelationshipMesh(segments: segments, thickness: relationshipThickness(relationship)) {
                var material = UnlitMaterial(color: relationshipColor(relationship))
                material.faceCulling = .none
                material.blending = .transparent(opacity: .init(scale: opacity))
                let entity = ModelEntity(mesh: core, materials: [material])
                entity.name = relationship.kind == .crossLink ? "cross-link-core" : "hierarchy-core"
                link.addChild(entity)
            }
            root.addChild(link)
            relationshipKeys[name] = key
        }
    }

    private func relationshipName(_ relationship: FocusSceneSnapshot.Relationship) -> String {
        "link-\(relationship.kind.rawValue)-\(relationship.sourceID)-\(relationship.targetID)"
    }

    private func visualStyle(for item: FocusSceneSnapshot.Item) -> NodeVisualStyle {
        NodeVisualStyle.resolve(
            kind: item.kind,
            attention: item.attention,
            hierarchyDepth: item.hierarchyDepth,
            urgency: item.urgency,
            isEnabled: item.isEnabled,
            shapePreference: shapePreference,
            isExpanded: item.isSelected && !item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    private func relationshipColor(_ relationship: FocusSceneSnapshot.Relationship) -> NSColor {
        relationship.kind == .crossLink
            ? NSColor(red: 0.54, green: 0.40, blue: 1, alpha: 1)
            : tokens.focusBlue.nsColor
    }

    private func relationshipOpacity(_ relationship: FocusSceneSnapshot.Relationship) -> Float {
        let emphasis: Float = switch relationship.emphasis {
        case .subdued: 0.18
        case .standard: 0.30
        case .branch: 0.42
        case .direct: 0.72
        }
        let attention = Float(0.52 + relationship.attention * 0.48)
        return emphasis * attention * (relationship.isDimmed ? 0.22 : 1)
    }

    private func relationshipThickness(_ relationship: FocusSceneSnapshot.Relationship) -> Float {
        switch relationship.emphasis {
        case .subdued: 0.004
        case .standard: 0.007
        case .branch: 0.010
        case .direct: 0.014
        }
    }

    private func makeRelationshipMesh(
        segments: [RelationshipCurveGeometry.Segment],
        thickness: Float
    ) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for segment in segments {
            appendLineQuad(
                from: segment.start,
                to: segment.end,
                thickness: thickness,
                positions: &positions,
                indices: &indices
            )
        }
        var descriptor = MeshDescriptor(name: "relationship-curve")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
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
                isEnabled: item.isEnabled,
                shapePreference: shapePreference,
                isExpanded: item.isSelected && !item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            let x = random.float(in: -12.0...12.0)
            let y = random.float(in: -7.2...7.2)
            let z = random.float(in: -8.2 ... -3.25)
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
        let rings: [(x: Float, y: Float, z: Float)] = [
            (2.2, 0.68, 0),
            (3.4, 1.16, -0.92),
            (4.8, 1.72, -2.02),
            (6.3, 2.35, -3.28)
        ]
        let segments = quality.guideSegmentCount
        let thickness: Float = quality == .efficient ? 0.008 : 0.011

        for ring in rings {
            for segment in 0..<segments {
                let startAngle = Float(segment) / Float(segments) * .pi * 2
                let endAngle = Float(segment + 1) / Float(segments) * .pi * 2
                let start = SIMD3<Float>(
                    cos(startAngle) * ring.x,
                    sin(startAngle) * ring.y - 0.2,
                    ring.z - abs(sin(startAngle * 2)) * 0.055
                )
                let end = SIMD3<Float>(
                    cos(endAngle) * ring.x,
                    sin(endAngle) * ring.y - 0.2,
                    ring.z - abs(sin(endAngle * 2)) * 0.055
                )
                appendLineQuad(from: start, to: end, thickness: thickness, positions: &positions, indices: &indices)
            }
        }

        for spoke in 0..<12 {
            let angle = Float(spoke) / 12 * .pi * 2
            let start = SIMD3<Float>(cos(angle) * 0.4, sin(angle) * 0.12 - 0.2, 0)
            let end = SIMD3<Float>(cos(angle) * 6.3, sin(angle) * 2.35 - 0.2, -3.34)
            appendLineQuad(from: start, to: end, thickness: thickness * 0.7, positions: &positions, indices: &indices)
        }

        var descriptor = MeshDescriptor(name: "orbital-guides")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        let mesh = try MeshResource.generate(from: [descriptor])
        var material = UnlitMaterial(color: tokens.focusBlue.nsColor)
        material.faceCulling = .none
        material.blending = .transparent(opacity: .init(scale: 1))
        let guides = ModelEntity(mesh: mesh, materials: [material])
        guides.name = "orbital-guides"
        guides.components.set(OpacityComponent(opacity: 0.08))
        return guides
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

private struct RelationshipRenderKey: Equatable {
    let relationship: FocusSceneSnapshot.Relationship
    let sourcePosition: SIMD3<Float>
    let sourceSize: SIMD2<Float>
    let targetPosition: SIMD3<Float>
    let targetSize: SIMD2<Float>
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
