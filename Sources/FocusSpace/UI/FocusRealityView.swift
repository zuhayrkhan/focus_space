import RealityKit
import SwiftUI

struct FocusRealityView: View {
    @ObservedObject var store: FocusSpaceStore
    @Binding var universeGuideOpacity: Double
    let nodeShapePreference: NodeShapePreference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("nodeLegendCorner") private var legendCornerRaw = LegendCorner.topTrailing.rawValue
    @State private var renderer = RealityFocusRenderer()
    @State private var dragOrigins: [UUID: SpatialPoint] = [:]
    @State private var dragAttentionOrigins: [UUID: Double] = [:]
    @State private var dragSnapshots: [UUID: FocusSceneSnapshot] = [:]
    @State private var depthDragIDs: Set<UUID> = []
    @State private var cameraDragOrigin: FocusCameraIntent.Pose?
    @State private var magnifyOrigin: FocusCameraIntent.Pose?
    @State private var rotationOrigin: FocusCameraIntent.Pose?
    @State private var controlsVisible = true
    @State private var controlsTask: Task<Void, Never>?
    @State private var idleReturnTask: Task<Void, Never>?
    @State private var isLegendInteracting = false
    @State private var navigationStartedOnLegend = false
    @State private var canvasSize = CGSize.zero
    @GestureState private var legendDragOffset = CGSize.zero

    var body: some View {
        RealityView { content in
            content.add(renderer.makeScene())
        } update: { content in
            guard let root = content.entities.first?.findEntity(named: RealityFocusRenderer.rootName)
                ?? content.entities.first(where: { $0.name == RealityFocusRenderer.rootName }) else { return }
            renderer.reconcile(
                root: root,
                snapshot: store.sceneSnapshot,
                shapePreference: nodeShapePreference
            )
            renderer.updateAmbient(root: root, reduceMotion: reduceMotion)
            renderer.updateCamera(root: root, intent: store.cameraIntent, reduceMotion: reduceMotion)
            renderer.updateGuideOpacity(root: root, opacity: universeGuideOpacity)
        }
        .gesture(
            magnifyGesture.simultaneously(
                with: selectionGesture.exclusively(before: emptySelectionGesture)
            )
        )
        .simultaneousGesture(renameGesture)
        .simultaneousGesture(moveGesture.exclusively(before: navigationGesture))
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
        .overlay(alignment: legendCorner.alignment) { nodeLegend }
        .overlay(alignment: .bottom) { navigationControls }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            canvasSize = newSize
        }
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

    private var emptySelectionGesture: some Gesture {
        SpatialTapGesture(count: 1)
            .onEnded { _ in
                store.hover(nil)
                store.select(nil)
            }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .targetedToAnyEntity()
            .onChanged { value in
                guard let id = nodeID(from: value.entity), let node = store.map.node(id: id) else { return }
                let origin = dragOrigins[id] ?? node.position
                let attentionOrigin = dragAttentionOrigins[id] ?? node.attention
                if dragOrigins[id] == nil {
                    store.beginInteraction()
                    dragSnapshots[id] = store.sceneSnapshot
                    dragAttentionOrigins[id] = node.attention
                    if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                        depthDragIDs.insert(id)
                    }
                }
                dragOrigins[id] = origin
                let dx = Double(value.translation.width / 115)
                let dy = Double(-value.translation.height / 115)
                let previewPosition = depthDragIDs.contains(id)
                    ? origin
                    : SpatialPoint(x: origin.x + dx, y: origin.y + dy)
                let previewAttention = depthDragIDs.contains(id)
                    ? min(max(attentionOrigin + dy * 0.015, 0), 1)
                    : attentionOrigin
                if let entity = nodeEntity(from: value.entity),
                   let snapshot = dragSnapshots[id],
                   let base = snapshot.items.first(where: { $0.id == id }) {
                    renderer.previewNodeDrag(
                        entity: entity,
                        item: previewItem(base, position: previewPosition, attention: previewAttention),
                        snapshot: snapshot
                    )
                }
            }
            .onEnded { value in
                if let id = nodeID(from: value.entity),
                   let origin = dragOrigins[id],
                   let attentionOrigin = dragAttentionOrigins[id] {
                    let dx = Double(value.translation.width / 115)
                    let dy = Double(-value.translation.height / 115)
                    if depthDragIDs.contains(id) {
                        store.setAttention(id, to: attentionOrigin + dy * 0.015)
                    } else {
                        store.move(id, to: SpatialPoint(x: origin.x + dx, y: origin.y + dy))
                    }
                    dragOrigins[id] = nil
                    dragAttentionOrigins[id] = nil
                    dragSnapshots[id] = nil
                    depthDragIDs.remove(id)
                }
                store.endInteraction()
            }
    }

    private var navigationGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if cameraDragOrigin == nil,
                   legendCorner.contains(value.startLocation, in: canvasSize) {
                    navigationStartedOnLegend = true
                }
                guard !isLegendInteracting, !navigationStartedOnLegend else {
                    cameraDragOrigin = nil
                    return
                }
                let origin = cameraDragOrigin ?? store.cameraIntent.pose
                if cameraDragOrigin == nil { noteNavigationActivity(scheduleIdleReturn: false) }
                cameraDragOrigin = origin
                let pose = store.orbitCameraPose(
                    horizontal: value.translation.width,
                    vertical: value.translation.height,
                    from: origin
                )
                renderer.previewCamera(pose: pose, reduceMotion: reduceMotion)
            }
            .onEnded { value in
                defer { navigationStartedOnLegend = false }
                guard !isLegendInteracting, !navigationStartedOnLegend else {
                    cameraDragOrigin = nil
                    return
                }
                if let origin = cameraDragOrigin {
                    store.setCameraPose(store.orbitCameraPose(
                        horizontal: value.translation.width,
                        vertical: value.translation.height,
                        from: origin
                    ))
                }
                cameraDragOrigin = nil
                noteNavigationActivity()
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.002)
            .onChanged { value in
                let origin = magnifyOrigin ?? store.cameraIntent.pose
                if magnifyOrigin == nil { noteNavigationActivity(scheduleIdleReturn: false) }
                magnifyOrigin = origin
                renderer.previewCamera(
                    pose: store.zoomCameraPose(by: value.magnification, from: origin),
                    reduceMotion: reduceMotion
                )
            }
            .onEnded { value in
                if let origin = magnifyOrigin {
                    store.setCameraPose(store.zoomCameraPose(by: value.magnification, from: origin))
                }
                magnifyOrigin = nil
                noteNavigationActivity()
            }
    }

    private var rotationGesture: some Gesture {
        RotateGesture(minimumAngleDelta: .degrees(1))
            .onChanged { value in
                let origin = rotationOrigin ?? store.cameraIntent.pose
                if rotationOrigin == nil { noteNavigationActivity(scheduleIdleReturn: false) }
                rotationOrigin = origin
                renderer.previewCamera(
                    pose: store.orbitCameraPose(
                        horizontal: value.rotation.degrees / 0.28,
                        vertical: 0,
                        from: origin
                    ),
                    reduceMotion: reduceMotion
                )
            }
            .onEnded { value in
                if let origin = rotationOrigin {
                    store.setCameraPose(store.orbitCameraPose(
                        horizontal: value.rotation.degrees / 0.28,
                        vertical: 0,
                        from: origin
                    ))
                }
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

    private var nodeLegend: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "circle.grid.2x2")
                Text("COLOUR KEY")
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption2.weight(.semibold))
            ForEach(FocusNodeKind.allCases) { kind in
                let style = NodeVisualStyle.resolve(
                    kind: kind,
                    attention: 0.82,
                    hierarchyDepth: 0,
                    urgency: .none,
                    isEnabled: true
                )
                HStack(spacing: 8) {
                    Circle()
                        .fill(style.color.color)
                        .frame(width: 9, height: 9)
                        .overlay { Circle().stroke(.white.opacity(0.48), lineWidth: 0.6) }
                    Text(kind.displayName)
                        .font(.caption)
                }
            }
        }
        .padding(11)
        .frame(width: 176)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.10)) }
        .shadow(color: .black.opacity(0.20), radius: 14, y: 7)
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, legendCorner.isBottom ? 46 : 14)
        .offset(legendDragOffset)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in isLegendInteracting = true }
                .updating($legendDragOffset) { value, offset, _ in
                    offset = value.translation
                }
                .onEnded { value in
                    legendCornerRaw = legendCorner
                        .moved(by: value.translation)
                        .rawValue
                    Task { @MainActor in
                        await Task.yield()
                        isLegendInteracting = false
                    }
                }
        )
        .help("Drag the colour key toward any corner to dock it there")
    }

    private var legendCorner: LegendCorner {
        LegendCorner(rawValue: legendCornerRaw) ?? .topTrailing
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

    private func previewItem(
        _ item: FocusSceneSnapshot.Item,
        position: SpatialPoint,
        attention: Double
    ) -> FocusSceneSnapshot.Item {
        FocusSceneSnapshot.Item(
            id: item.id,
            title: item.title,
            notes: item.notes,
            kind: item.kind,
            position: position,
            attention: attention,
            parentID: item.parentID,
            hierarchyDepth: item.hierarchyDepth,
            urgency: item.urgency,
            isEnabled: item.isEnabled,
            isSelected: item.isSelected,
            isDimmed: item.isDimmed,
            isHovered: item.isHovered,
            contextRole: item.contextRole
        )
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

private enum LegendCorner: String {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }

    var isBottom: Bool {
        switch self {
        case .bottomLeading, .bottomTrailing: true
        case .topLeading, .topTrailing: false
        }
    }

    func contains(_ point: CGPoint, in size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        let horizontalInset: CGFloat = 210
        let verticalInset: CGFloat = isBottom ? 205 : 175
        let isInHorizontalRegion = switch self {
        case .topLeading, .bottomLeading: point.x <= horizontalInset
        case .topTrailing, .bottomTrailing: point.x >= size.width - horizontalInset
        }
        let isInVerticalRegion = switch self {
        case .topLeading, .topTrailing: point.y <= verticalInset
        case .bottomLeading, .bottomTrailing: point.y >= size.height - verticalInset
        }
        return isInHorizontalRegion && isInVerticalRegion
    }

    func moved(by translation: CGSize) -> Self {
        let isLeading: Bool = if translation.width < -70 {
            true
        } else if translation.width > 70 {
            false
        } else {
            switch self {
            case .topLeading, .bottomLeading: true
            case .topTrailing, .bottomTrailing: false
            }
        }
        let isTop: Bool = if translation.height < -70 {
            true
        } else if translation.height > 70 {
            false
        } else {
            switch self {
            case .topLeading, .topTrailing: true
            case .bottomLeading, .bottomTrailing: false
            }
        }
        return switch (isLeading, isTop) {
        case (true, true): .topLeading
        case (false, true): .topTrailing
        case (true, false): .bottomLeading
        default: .bottomTrailing
        }
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
