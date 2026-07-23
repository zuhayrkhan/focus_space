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
    private var relationshipKeys: [String: RelationshipRenderKey] = [:]
    private var shapePreference: NodeShapePreference = .semantic
    private var highContrast = false
    private var textScale: Float = 1
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
        shapePreference: NodeShapePreference = .semantic,
        highContrast: Bool = false,
        textScale: Float = 1,
        reduceMotion: Bool = false
    ) {
        let shapeChanged = self.shapePreference != shapePreference
        let accessibilityChanged = self.highContrast != highContrast || self.textScale != textScale
        guard lastSnapshot != snapshot || shapeChanged || accessibilityChanged else { return }
        self.shapePreference = shapePreference
        self.highContrast = highContrast
        self.textScale = textScale
        if accessibilityChanged { relationshipKeys.removeAll() }
        let previousItems = shapeChanged || accessibilityChanged
            ? [:]
            : Dictionary(uniqueKeysWithValues: (lastSnapshot?.items ?? []).map { ($0.id, $0) })

        let visibleItems = snapshot.items.filter { $0.presentationLevel.isSpatiallyVisible }
        let desiredIDs = Set(visibleItems.map { $0.id.uuidString })
        for child in root.children where child.name.hasPrefix("node-") {
            let id = String(child.name.dropFirst(5))
            if !desiredIDs.contains(id) { child.removeFromParent() }
        }

        for item in visibleItems {
            let name = "node-\(item.id.uuidString)"
            let entity = root.findEntity(named: name) ?? makeNode(name: name)
            if entity.parent == nil { root.addChild(entity) }
            update(entity: entity, for: item, previous: previousItems[item.id], reduceMotion: reduceMotion)
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
            .filter { $0.presentationLevel.isSpatiallyVisible }
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
            camera.move(to: transform, relativeTo: root, duration: FocusMotion.cameraDuration, timingFunction: .easeInOut)
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
        previewNodeDrag(items: [item], snapshot: snapshot)
    }

    func previewNodeDrag(
        items: [FocusSceneSnapshot.Item],
        snapshot: FocusSceneSnapshot
    ) {
        previewItems(items, snapshot: snapshot)
    }

    func previewDepthDrag(
        items: [FocusSceneSnapshot.Item],
        snapshot: FocusSceneSnapshot
    ) {
        previewItems(items, snapshot: snapshot)
    }

    private func previewItems(
        _ items: [FocusSceneSnapshot.Item],
        snapshot: FocusSceneSnapshot
    ) {
        guard let sceneRoot else { return }
        let replacements = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for item in items {
            guard let entity = sceneRoot.findEntity(named: "node-\(item.id.uuidString)") else { continue }
            entity.position = position(for: item)
            let depthScale = Float(0.78 + item.attention * 0.24)
            entity.scale = SIMD3<Float>(repeating: depthScale * item.presentationLevel.scale)
        }
        let preview = FocusSceneSnapshot(
            items: snapshot.items.map { replacements[$0.id] ?? $0 },
            relationships: snapshot.relationships,
            workspacePresentationLevel: snapshot.workspacePresentationLevel,
            islands: snapshot.islands
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
        let mesh = mesh(for: style)
        let entity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
        entity.name = name
        entity.components.set(InputTargetComponent())
        entity.generateCollisionShapes(recursive: false)
        return entity
    }

    private func update(
        entity: Entity,
        for item: FocusSceneSnapshot.Item,
        previous: FocusSceneSnapshot.Item?,
        reduceMotion: Bool
    ) {
        let style = NodeVisualStyle.resolve(
            kind: item.kind,
            attention: item.attention,
            hierarchyDepth: item.hierarchyDepth,
            urgency: item.urgency,
            isEnabled: item.isEnabled,
            shapePreference: shapePreference,
            isExpanded: item.presentationLevel == .atlas
                || item.isSelected && !item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            colorVariation: colorVariation(for: item.id)
        )
        let targetPosition = position(for: item)
        let depthScale = Float(0.78 + item.attention * 0.24)
        let targetScale = SIMD3<Float>(repeating: depthScale * item.presentationLevel.scale)
        let presentationChanged = previous?.presentationLevel != item.presentationLevel
            || previous?.renderPosition != item.renderPosition
        if let previous,
           !reduceMotion,
           presentationChanged || previous.attention != item.attention && item.isGravityInfluenced {
            let target = Transform(
                scale: targetScale,
                rotation: entity.transform.rotation,
                translation: targetPosition
            )
            entity.stopAllAnimations(recursive: false)
            entity.move(
                to: target,
                relativeTo: entity.parent,
                duration: presentationChanged ? FocusMotion.cameraDuration : FocusMotion.gravityDuration,
                timingFunction: .easeInOut
            )
        } else {
            entity.position = targetPosition
            entity.scale = targetScale
        }
        guard needsVisualUpdate(from: previous, to: item) else { return }
        let contextOpacity: Float = switch item.contextRole {
        case .subdued: highContrast ? 0.68 : 0.50
        case .none, .branch, .direct: 1
        }
        let visibleOpacity = highContrast ? max(style.opacity, 0.72) : style.opacity
        entity.components.set(OpacityComponent(
            opacity: item.isDimmed ? (highContrast ? 0.15 : 0.06) : visibleOpacity * contextOpacity
        ))
        guard let model = entity as? ModelEntity else { return }
        model.model?.mesh = mesh(for: style)
        model.generateCollisionShapes(recursive: false)
        updateInteractionTarget(on: model, item: item, style: style)
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

    private func updateInteractionTarget(
        on entity: ModelEntity,
        item: FocusSceneSnapshot.Item,
        style: NodeVisualStyle
    ) {
        for child in entity.children where child.name == "semantic-hit-target" {
            child.removeFromParent()
        }
        guard item.presentationLevel.requiresExpandedHitTarget else { return }
        let inverseScale = 1 / max(item.presentationLevel.scale, 0.01)
        let target = Entity()
        target.name = "semantic-hit-target"
        target.position.z = 0.01
        target.components.set(InputTargetComponent())
        target.components.set(CollisionComponent(shapes: [
            .generateBox(size: SIMD3<Float>(
                max(style.width, 1.18 * inverseScale),
                max(style.height, 0.62 * inverseScale),
                0.03
            ))
        ]))
        entity.addChild(target)
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
            || previous.manualAttention != item.manualAttention
            || previous.gravityReason != item.gravityReason
            || previous.isGravityInfluenced != item.isGravityInfluenced
            || previous.hierarchyDepth != item.hierarchyDepth
            || previous.urgency != item.urgency
            || previous.isEnabled != item.isEnabled
            || previous.isSelected != item.isSelected
            || previous.isDimmed != item.isDimmed
            || previous.isHovered != item.isHovered
            || previous.contextRole != item.contextRole
            || previous.presentationLevel != item.presentationLevel
            || previous.renderPosition != item.renderPosition
            || previous.presentationSummary != item.presentationSummary
    }

    private func mesh(for style: NodeVisualStyle) -> MeshResource {
        mesh(
            silhouette: style.silhouette,
            width: style.width,
            height: style.height,
            cornerRadius: style.cornerRadius,
            depth: 0.15
        )
    }

    private func mesh(
        silhouette: NodeSilhouette,
        width: Float,
        height: Float,
        cornerRadius: Float,
        depth: Float
    ) -> MeshResource {
        let key = "\(silhouette)-\(width)-\(height)-\(cornerRadius)-\(depth)"
        if let cached = nodeMeshes[key] { return cached }
        let mesh: MeshResource = switch silhouette {
        case .ellipse, .circle:
            (try? makeRadialPrismMesh(width: width, height: height, depth: depth, segments: 48))
                ?? .generateBox(width: width, height: height, depth: depth, cornerRadius: min(width, height) / 2)
        case .diamond:
            (try? makeRadialPrismMesh(width: width, height: height, depth: depth, segments: 4))
                ?? .generateBox(width: width, height: height, depth: depth, cornerRadius: 0)
        case .panel, .capsule, .compact, .note, .ghost:
            .generateBox(width: width, height: height, depth: depth, cornerRadius: cornerRadius)
        }
        nodeMeshes[key] = mesh
        return mesh
    }

    private func makeRadialPrismMesh(
        width: Float,
        height: Float,
        depth: Float,
        segments: Int
    ) throws -> MeshResource {
        let halfWidth = width / 2
        let halfHeight = height / 2
        let halfDepth = depth / 2
        let step = Float.pi * 2 / Float(segments)
        let points = (0..<segments).map { index in
            let angle = Float(index) * step
            return SIMD2<Float>(cos(angle) * halfWidth, sin(angle) * halfHeight)
        }
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        let frontCenter = UInt32(positions.count)
        positions.append(SIMD3<Float>(0, 0, halfDepth))
        normals.append(SIMD3<Float>(0, 0, 1))
        let frontStart = UInt32(positions.count)
        for point in points {
            positions.append(SIMD3<Float>(point.x, point.y, halfDepth))
            normals.append(SIMD3<Float>(0, 0, 1))
        }
        for index in 0..<segments {
            let next = (index + 1) % segments
            indices += [frontCenter, frontStart + UInt32(index), frontStart + UInt32(next)]
        }

        let backCenter = UInt32(positions.count)
        positions.append(SIMD3<Float>(0, 0, -halfDepth))
        normals.append(SIMD3<Float>(0, 0, -1))
        let backStart = UInt32(positions.count)
        for point in points {
            positions.append(SIMD3<Float>(point.x, point.y, -halfDepth))
            normals.append(SIMD3<Float>(0, 0, -1))
        }
        for index in 0..<segments {
            let next = (index + 1) % segments
            indices += [backCenter, backStart + UInt32(next), backStart + UInt32(index)]
        }

        for index in 0..<segments {
            let next = (index + 1) % segments
            let first = points[index]
            let second = points[next]
            let midpointAngle = (Float(index) + 0.5) * step
            let rawNormal = SIMD3<Float>(
                cos(midpointAngle) / max(halfWidth, 0.001),
                sin(midpointAngle) / max(halfHeight, 0.001),
                0
            )
            let normal = simd_normalize(rawNormal)
            let start = UInt32(positions.count)
            positions += [
                SIMD3<Float>(first.x, first.y, halfDepth),
                SIMD3<Float>(second.x, second.y, halfDepth),
                SIMD3<Float>(second.x, second.y, -halfDepth),
                SIMD3<Float>(first.x, first.y, -halfDepth)
            ]
            normals += Array(repeating: normal, count: 4)
            indices += [start, start + 1, start + 2, start, start + 2, start + 3]
        }

        var descriptor = MeshDescriptor(name: "radial-node-prism")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
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
        let title = NodeLabelLayout.displayTitle(
            item.title,
            maximumCharacters: item.presentationLevel.maximumLabelCharacters,
            singleLineLimit: singleLineLimit
        )
        let notes = NodeNotesLayout.displayText(item.presentationSummary ?? item.notes)
        let showsNotes = item.presentationLevel == .atlas
            || item.isSelected && !notes.isEmpty
        let attentionBand = Int(item.attention * 20)
        let decorationName = "decorations-\(style.silhouette)-\(style.width)-\(style.height)-\(item.kind.rawValue)-\(item.urgency.rawValue)-\(item.isEnabled)-\(item.isSelected)-\(item.isHovered)-\(item.contextRole)-\(item.presentationLevel)-\(attentionBand)-\(textScale)-\(highContrast)-\(title)-\(notes.hashValue)"
        if entity.children.contains(where: { $0.name == decorationName }) { return }
        for child in entity.children where child.name.hasPrefix("decorations-") { child.removeFromParent() }

        let decorations = Entity()
        decorations.name = decorationName
        decorations.addChild(makeSilhouetteLayer(
            style: style,
            expansion: item.kind == .project ? 0.055 : 0.035,
            depth: 0.13,
            color: style.color.nsColor,
            opacity: style.borderOpacity,
            name: "kind-edge",
            z: -0.018
        ))

        let font = NSFont.systemFont(
            ofSize: 0.13 * CGFloat(textScale) * item.presentationLevel.labelScale,
            weight: item.isSelected ? .semibold : .medium
        )
        let mesh = MeshResource.generateText(
            title,
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
        let baseLabelAlpha = item.isDimmed
            ? (highContrast ? 0.38 : 0.2)
            : (highContrast ? 1 : 0.76 + item.attention * 0.24)
        let labelAlpha = baseLabelAlpha * item.presentationLevel.labelOpacity
        let material = UnlitMaterial(color: NSColor(white: 0.98, alpha: labelAlpha))
        let label = ModelEntity(mesh: mesh, materials: [material])
        label.name = "node-label"
        let labelBounds = label.visualBounds(relativeTo: label)
        label.position = SIMD3<Float>(
            -labelBounds.center.x,
            showsNotes ? style.height / 2 - 0.38 : -labelBounds.center.y,
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
                font: .systemFont(
                    ofSize: 0.092 * CGFloat(textScale),
                    weight: highContrast ? .medium : .regular
                ),
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
            item.presentationLevel.showsKindGlyph ? style.glyph : "",
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
            decorations.addChild(makeSilhouetteLayer(
                style: style,
                expansion: 0.16,
                depth: 0.016,
                color: style.color.nsColor,
                opacity: 0.13,
                name: "selection-haze-inner",
                z: -0.095
            ))
            decorations.addChild(makeSilhouetteLayer(
                style: style,
                expansion: 0.36,
                depth: 0.010,
                color: style.color.nsColor,
                opacity: 0.035,
                name: "selection-haze-outer",
                z: -0.102
            ))
        }

        if item.isHovered {
            decorations.addChild(makeSilhouetteLayer(
                style: style,
                expansion: 0.16,
                depth: 0.012,
                color: tokens.focusCore.nsColor,
                opacity: 0.18,
                name: "hover-haze",
                z: -0.09
            ))
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

    private func makeSilhouetteLayer(
        style: NodeVisualStyle,
        expansion: Float,
        depth: Float,
        color: NSColor,
        opacity: Float,
        name: String,
        z: Float
    ) -> ModelEntity {
        let mesh = mesh(
            silhouette: style.silhouette,
            width: style.width + expansion,
            height: style.height + expansion,
            cornerRadius: style.cornerRadius + expansion * 0.24,
            depth: depth
        )
        var material = UnlitMaterial(color: color)
        material.faceCulling = .none
        material.blending = .transparent(opacity: .init(scale: opacity))
        let layer = ModelEntity(mesh: mesh, materials: [material])
        layer.name = name
        layer.position.z = z
        return layer
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
            let sourceScale = Float(0.78 + source.attention * 0.24) * source.presentationLevel.scale
            let targetScale = Float(0.78 + target.attention * 0.24) * target.presentationLevel.scale
            let name = relationshipName(relationship)
            let key = RelationshipRenderKey(
                relationship: relationship,
                sourcePosition: position(for: source),
                sourceSize: SIMD2<Float>(sourceStyle.width, sourceStyle.height) * sourceScale,
                sourceShape: sourceStyle.silhouette,
                targetPosition: position(for: target),
                targetSize: SIMD2<Float>(targetStyle.width, targetStyle.height) * targetScale,
                targetShape: targetStyle.silhouette
            )
            if relationshipKeys[name] == key, root.findEntity(named: name) != nil { continue }
            root.findEntity(named: name)?.removeFromParent()
            let curve = RelationshipCurveGeometry.make(
                from: key.sourcePosition,
                sourceSize: key.sourceSize,
                to: key.targetPosition,
                targetSize: key.targetSize,
                kind: relationship.kind,
                sourceShape: key.sourceShape,
                targetShape: key.targetShape,
                sampleCount: quality == .efficient ? 28 : 42
            )
            let pointRuns = curve.pointRuns(for: relationship.kind)
            let link = Entity()
            link.name = name
            let opacity = relationshipOpacity(relationship)
            let showsGlow = relationship.emphasis == .branch || relationship.emphasis == .direct
            if showsGlow,
               let glow = try? makeRelationshipMesh(pointRuns: pointRuns, thickness: relationshipThickness(relationship) * 1.8) {
                var material = UnlitMaterial(color: relationshipColor(relationship))
                material.faceCulling = .none
                material.blending = .transparent(opacity: .init(scale: opacity * 0.16))
                let entity = ModelEntity(mesh: glow, materials: [material])
                entity.name = "link-glow"
                entity.position.z = -0.006
                link.addChild(entity)
            }
            if let core = try? makeRelationshipMesh(pointRuns: pointRuns, thickness: relationshipThickness(relationship)) {
                var material = UnlitMaterial(color: relationshipColor(relationship))
                material.faceCulling = .none
                material.blending = .transparent(opacity: .init(scale: opacity))
                let entity = ModelEntity(mesh: core, materials: [material])
                entity.name = relationship.kind == .crossLink ? "cross-link-core" : "hierarchy-core"
                entity.position.z = 0.004
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
            isExpanded: item.presentationLevel == .atlas
                || item.isSelected && !item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            colorVariation: colorVariation(for: item.id)
        )
    }

    private func colorVariation(for id: UUID) -> Double {
        let hash = id.uuidString.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return Double(hash % 1_001) / 1_000
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
        let result = emphasis * attention * (relationship.isDimmed ? (highContrast ? 0.38 : 0.22) : 1)
        return highContrast ? max(result, relationship.isDimmed ? 0.14 : 0.34) : result
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
        pointRuns: [[SIMD3<Float>]],
        thickness: Float
    ) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for points in pointRuns where points.count > 1 {
            let base = UInt32(positions.count)
            for index in points.indices {
                let previous = points[index == points.startIndex ? index : points.index(before: index)]
                let next = points[index == points.index(before: points.endIndex) ? index : points.index(after: index)]
                let tangent = next - previous
                let planarLength = max(simd_length(SIMD2<Float>(tangent.x, tangent.y)), 0.0001)
                let normal = SIMD3<Float>(-tangent.y / planarLength, tangent.x / planarLength, 0) * thickness
                positions.append(points[index] - normal)
                positions.append(points[index] + normal)
            }
            for index in 0..<(points.count - 1) {
                let start = base + UInt32(index * 2)
                indices.append(contentsOf: [start, start + 1, start + 2, start + 2, start + 1, start + 3])
            }
        }
        var descriptor = MeshDescriptor(name: "relationship-curve")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    private func position(for item: FocusSceneSnapshot.Item) -> SIMD3<Float> {
        let range = tokens.attentionNearZ - tokens.attentionFarZ
        let renderPosition = item.renderPosition ?? item.position
        return SIMD3<Float>(
            Float(renderPosition.x),
            Float(renderPosition.y) + NodeVisualStyle.resolve(
                kind: item.kind,
                attention: item.attention,
                hierarchyDepth: item.hierarchyDepth,
                urgency: item.urgency,
                isEnabled: item.isEnabled,
                shapePreference: shapePreference,
                isExpanded: item.presentationLevel == .atlas
                    || item.isSelected && !item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    let sourceShape: NodeSilhouette
    let targetPosition: SIMD3<Float>
    let targetSize: SIMD2<Float>
    let targetShape: NodeSilhouette
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
