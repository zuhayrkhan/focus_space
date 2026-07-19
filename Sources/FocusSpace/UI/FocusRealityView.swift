import RealityKit
import SwiftUI

struct FocusRealityView: View {
    @ObservedObject var store: FocusSpaceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renderer = RealityFocusRenderer()
    @State private var dragOrigins: [UUID: SpatialPoint] = [:]
    @State private var cameraDragOrigin: FocusCameraIntent.Pose?
    @State private var magnifyOrigin: FocusCameraIntent.Pose?
    @State private var rotationOrigin: FocusCameraIntent.Pose?
    @State private var controlsVisible = true
    @State private var controlsTask: Task<Void, Never>?
    @State private var idleReturnTask: Task<Void, Never>?

    var body: some View {
        RealityView { content in
            content.add(renderer.makeScene())
        } update: { content in
            guard let root = content.entities.first?.findEntity(named: RealityFocusRenderer.rootName)
                ?? content.entities.first(where: { $0.name == RealityFocusRenderer.rootName }) else { return }
            renderer.reconcile(root: root, snapshot: store.sceneSnapshot)
            renderer.updateAmbient(root: root, reduceMotion: reduceMotion)
            renderer.updateCamera(root: root, intent: store.cameraIntent, reduceMotion: reduceMotion)
        }
        .gesture(selectionGesture)
        .simultaneousGesture(renameGesture)
        .simultaneousGesture(moveGesture.exclusively(before: navigationGesture))
        .simultaneousGesture(magnifyGesture)
        .simultaneousGesture(rotationGesture)
        .simultaneousGesture(hoverGesture)
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
            Text("Drag nodes to arrange · drag empty space to move the universe · ⌘0 resets")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(14)
        }
        .overlay(alignment: .bottom) { navigationControls }
        .onAppear { noteNavigationActivity() }
        .onDisappear {
            controlsTask?.cancel()
            idleReturnTask?.cancel()
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
                if let entity = nodeEntity(from: value.entity),
                   let item = store.sceneSnapshot.items.first(where: { $0.id == id }) {
                    renderer.previewNodeTransform(entity: entity, item: item)
                }
            }
            .onEnded { value in
                if let id = nodeID(from: value.entity) { dragOrigins[id] = nil }
                store.endInteraction()
            }
    }

    private var navigationGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let origin = cameraDragOrigin ?? store.cameraIntent.pose
                cameraDragOrigin = origin
                noteNavigationActivity(scheduleIdleReturn: false)
                store.orbitCamera(
                    horizontal: value.translation.width,
                    vertical: value.translation.height,
                    from: origin
                )
                renderer.previewCamera(intent: store.cameraIntent, reduceMotion: reduceMotion)
            }
            .onEnded { _ in
                cameraDragOrigin = nil
                noteNavigationActivity()
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                let origin = magnifyOrigin ?? store.cameraIntent.pose
                magnifyOrigin = origin
                store.zoomCamera(by: value.magnification, from: origin)
                noteNavigationActivity(scheduleIdleReturn: false)
            }
            .onEnded { _ in
                magnifyOrigin = nil
                noteNavigationActivity()
            }
    }

    private var rotationGesture: some Gesture {
        RotateGesture(minimumAngleDelta: .degrees(1))
            .onChanged { value in
                let origin = rotationOrigin ?? store.cameraIntent.pose
                rotationOrigin = origin
                store.orbitCamera(horizontal: value.rotation.degrees / 0.28, vertical: 0, from: origin)
                noteNavigationActivity(scheduleIdleReturn: false)
            }
            .onEnded { _ in
                rotationOrigin = nil
                noteNavigationActivity()
            }
    }

    private var hoverGesture: some Gesture {
        SpatialEventGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                guard value.gestureValue.contains(where: { $0.kind == .pointer && $0.phase == .active }) else { return }
                store.hover(nodeID(from: value.entity))
            }
            .onEnded { _ in store.hover(nil) }
    }

    private var navigationControls: some View {
        HStack(spacing: 5) {
            Label("Move universe", systemImage: "rotate.3d")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            Divider().frame(height: 22)
            Button("Zoom out", systemImage: "minus.magnifyingglass") {
                store.zoomCamera(by: 0.84, animated: true)
                noteNavigationActivity()
            }
            .labelStyle(.iconOnly)
            Button("Zoom in", systemImage: "plus.magnifyingglass") {
                store.zoomCamera(by: 1.18, animated: true)
                noteNavigationActivity()
            }
            .labelStyle(.iconOnly)
            Button("Frame branch", systemImage: "viewfinder") {
                store.frameSelection()
                noteNavigationActivity(scheduleIdleReturn: false)
            }
            .labelStyle(.iconOnly)
            .disabled(!store.canFrameSelection)
            Button("Reset view", systemImage: "arrow.counterclockwise") {
                store.resetCamera()
                noteNavigationActivity(scheduleIdleReturn: false)
            }
            .labelStyle(.iconOnly)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 13))
        .overlay { RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.10)) }
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
        .padding(.bottom, 12)
        .opacity(controlsVisible ? 1 : 0.16)
        .onHover { hovering in
            if hovering { controlsVisible = true; controlsTask?.cancel() }
            else { noteNavigationActivity() }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: controlsVisible)
    }

    private func noteNavigationActivity(scheduleIdleReturn: Bool = true) {
        controlsVisible = true
        controlsTask?.cancel()
        controlsTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            controlsVisible = false
        }
        idleReturnTask?.cancel()
        guard scheduleIdleReturn else { return }
        idleReturnTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled,
                  store.selection == nil,
                  store.editingNodeID == nil,
                  store.cameraIntent.mode == .free else { return }
            store.resetCamera(animated: true)
        }
    }

    private func nodeID(from entity: Entity) -> UUID? {
        nodeEntity(from: entity).flatMap { UUID(uuidString: String($0.name.dropFirst(5))) }
    }

    private func nodeEntity(from entity: Entity) -> Entity? {
        var candidate: Entity? = entity
        while let current = candidate {
            if current.name.hasPrefix("node-") {
                return current
            }
            candidate = current.parent
        }
        return nil
    }
}

private struct WorkspaceBackground: View {
    private let tokens = FocusVisualTokens.midnight

    var body: some View {
        ZStack {
            tokens.canvasDeep.color
            RadialGradient(
                colors: [tokens.canvasMid.color.opacity(0.92), tokens.canvasDeep.color.opacity(0.2), .clear],
                center: UnitPoint(x: 0.5, y: 0.12),
                startRadius: 12,
                endRadius: 680
            )
            RadialGradient(
                colors: [tokens.focusBlue.color.opacity(0.09), .clear],
                center: UnitPoint(x: 0.5, y: 0.58),
                startRadius: 20,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}
