import RealityKit
import SwiftUI

struct FocusRealityView: View {
    @ObservedObject var store: FocusSpaceStore
    @State private var renderer = RealityFocusRenderer()
    @State private var dragOrigins: [UUID: SpatialPoint] = [:]

    var body: some View {
        RealityView { content in
            content.add(renderer.makeScene())
        } update: { content in
            guard let root = content.entities.first?.findEntity(named: RealityFocusRenderer.rootName)
                ?? content.entities.first(where: { $0.name == RealityFocusRenderer.rootName }) else { return }
            renderer.reconcile(root: root, snapshot: store.sceneSnapshot)
        }
        .gesture(selectionGesture)
        .simultaneousGesture(renameGesture)
        .simultaneousGesture(moveGesture)
        .contextMenu {
            if let id = store.selection {
                Button("Add Child") { store.addChild(to: id) }
                Button("Add Sibling") { store.addSibling(to: id) }
                Button("Duplicate") { store.duplicate(id) }
                Divider()
                Button("Pull Forward") { store.shiftAttention(id, by: 0.12) }
                Button("Push Back") { store.shiftAttention(id, by: -0.12) }
                Divider()
                Button("Delete", role: .destructive) { store.delete(id) }
            } else {
                Button("Add Thought") { store.addChild(to: nil) }
            }
        }
        .background(WorkspaceBackground())
        .overlay(alignment: .bottomLeading) {
            Text("Drag to arrange · ⌥ drag vertically to change depth · double-click to rename")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(14)
        }
    }

    private var selectionGesture: some Gesture {
        SpatialTapGesture(count: 1)
            .targetedToAnyEntity()
            .onEnded { value in
                store.select(nodeID(from: value.entity))
            }
    }

    private var renameGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .targetedToAnyEntity()
            .onEnded { value in
                if let id = nodeID(from: value.entity) { store.beginRenaming(id) }
            }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .targetedToAnyEntity()
            .onChanged { value in
                guard let id = nodeID(from: value.entity), let node = store.map.node(id: id) else { return }
                let origin = dragOrigins[id] ?? node.position
                if dragOrigins[id] == nil { store.beginInteraction() }
                dragOrigins[id] = origin
                let dx = Double(value.translation.width / 115)
                let dy = Double(-value.translation.height / 115)
                if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                    store.setAttention(id, to: node.attention + dy * 0.015)
                } else {
                    store.move(id, to: SpatialPoint(x: origin.x + dx, y: origin.y + dy))
                }
            }
            .onEnded { value in
                if let id = nodeID(from: value.entity) { dragOrigins[id] = nil }
                store.endInteraction()
            }
    }

    private func nodeID(from entity: Entity) -> UUID? {
        var candidate: Entity? = entity
        while let current = candidate {
            if current.name.hasPrefix("node-") {
                return UUID(uuidString: String(current.name.dropFirst(5)))
            }
            candidate = current.parent
        }
        return nil
    }
}

private struct WorkspaceBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.045, blue: 0.07)
            RadialGradient(
                colors: [Color.blue.opacity(0.18), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 620
            )
        }
        .ignoresSafeArea()
    }
}
