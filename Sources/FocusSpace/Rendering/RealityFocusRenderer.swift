import RealityKit
import SwiftUI

@MainActor
final class RealityFocusRenderer {
    static let rootName = "focus-space-root"

    func makeScene() -> Entity {
        let root = Entity()
        root.name = Self.rootName

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 42
        camera.position = SIMD3<Float>(0, 0.15, 8.7)
        root.addChild(camera)

        let key = DirectionalLight()
        key.light.color = .init(red: 0.75, green: 0.84, blue: 1, alpha: 1)
        key.light.intensity = 2_300
        key.orientation = simd_quatf(angle: -.pi / 4, axis: SIMD3<Float>(1, 0.3, 0))
        root.addChild(key)

        let fill = PointLight()
        fill.light.color = .init(red: 0.38, green: 0.48, blue: 1, alpha: 1)
        fill.light.intensity = 4_000
        fill.light.attenuationRadius = 12
        fill.position = SIMD3<Float>(-3, 2, 5)
        root.addChild(fill)
        return root
    }

    func reconcile(root: Entity, snapshot: FocusSceneSnapshot) {
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

    private func makeNode(name: String) -> ModelEntity {
        let mesh = MeshResource.generateBox(width: 1.42, height: 0.62, depth: 0.15, cornerRadius: 0.12)
        let entity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
        entity.name = name
        entity.components.set(InputTargetComponent())
        entity.generateCollisionShapes(recursive: false)
        return entity
    }

    private func update(entity: Entity, for item: FocusSceneSnapshot.Item) {
        let z = Float(-2.2 + item.attention * 3.1)
        entity.position = SIMD3<Float>(Float(item.position.x), Float(item.position.y), z)
        entity.components.set(OpacityComponent(opacity: item.isDimmed ? 0.09 : 1))
        let selectedScale: Float = item.isSelected ? 1.08 : 1
        entity.scale = SIMD3<Float>(repeating: selectedScale)

        guard let model = entity as? ModelEntity else { return }
        let warmth = Float(item.attention)
        let color = NSColor(
            red: CGFloat(0.18 + warmth * 0.18),
            green: CGFloat(0.25 + warmth * 0.18),
            blue: CGFloat(0.42 + warmth * 0.42),
            alpha: item.isSelected ? 1 : 0.88
        )
        model.model?.materials = [PhysicallyBasedMaterial.focusSpace(color: color, selected: item.isSelected)]
        updateLabel(on: model, item: item)
    }

    private func updateLabel(on entity: ModelEntity, item: FocusSceneSnapshot.Item) {
        let labelName = "label-\(item.title)"
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
        let material = UnlitMaterial(color: NSColor(white: 0.97, alpha: item.isDimmed ? 0.25 : 0.96))
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
            let mesh = MeshResource.generateBox(width: length, height: 0.012, depth: 0.012)
            let material = UnlitMaterial(color: NSColor(white: 0.6, alpha: 0.24))
            let link = ModelEntity(mesh: mesh, materials: [material])
            link.name = "link-\(parentID)-\(child.id)"
            link.position = (start + end) / 2
            link.orientation = simd_quatf(from: SIMD3<Float>(1, 0, 0), to: vector / length)
            root.addChild(link)
        }
    }

    private func position(for item: FocusSceneSnapshot.Item) -> SIMD3<Float> {
        SIMD3<Float>(Float(item.position.x), Float(item.position.y), Float(-2.2 + item.attention * 3.1))
    }
}

private extension PhysicallyBasedMaterial {
    static func focusSpace(color: NSColor, selected: Bool) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = 0.26
        material.metallic = 0.08
        if selected {
            material.emissiveColor = .init(color: NSColor(red: 0.2, green: 0.42, blue: 1, alpha: 1))
            material.emissiveIntensity = 0.22
        }
        return material
    }
}
