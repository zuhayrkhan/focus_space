import RealityKit
import SwiftUI

struct FocusRealityView: View {
    @ObservedObject var store: FocusSpaceStore
    @Binding var universeGuideOpacity: Double
    @Binding var colourKeyVisible: Bool
    let nodeShapePreference: NodeShapePreference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("nodeLegendCorner") private var legendCornerRaw = LegendCorner.topTrailing.rawValue
    @State private var renderer = RealityFocusRenderer()
    @State private var dragOrigins: [UUID: SpatialPoint] = [:]
    @State private var dragSnapshots: [UUID: FocusSceneSnapshot] = [:]
    @State private var depthDragSession: DepthDragSession?
    @State private var cameraDragOrigin: FocusCameraIntent.Pose?
    @State private var magnifyOrigin: FocusCameraIntent.Pose?
    @State private var trackpadPanOrigin: FocusCameraIntent.Pose?
    @State private var rotationOrigin: FocusCameraIntent.Pose?
    @State private var controlsVisible = true
    @State private var controlsTask: Task<Void, Never>?
    @State private var idleReturnTask: Task<Void, Never>?
    @State private var isLegendInteracting = false
    @State private var navigationStartedOnLegend = false
    @State private var canvasSize = CGSize.zero
    @GestureState private var legendDragOffset = CGSize.zero
    @FocusState private var canvasFocused: Bool

    var body: some View {
        RealityView { content in
            content.add(renderer.makeScene())
        } update: { content in
            guard let root = content.entities.first?.findEntity(named: RealityFocusRenderer.rootName)
                ?? content.entities.first(where: { $0.name == RealityFocusRenderer.rootName }) else { return }
            renderer.reconcile(
                root: root,
                snapshot: store.sceneSnapshot,
                shapePreference: differentiateWithoutColor ? .semantic : nodeShapePreference,
                highContrast: colorSchemeContrast == .increased,
                textScale: rendererTextScale
            )
            renderer.updateAmbient(root: root, reduceMotion: reduceMotion)
            renderer.updateCamera(root: root, intent: store.cameraIntent, reduceMotion: reduceMotion)
            renderer.updateGuideOpacity(root: root, opacity: universeGuideOpacity)
        }
        .background {
            TrackpadMagnificationBridge(
                onBegan: beginMagnification,
                onChanged: updateMagnification,
                onEnded: endMagnification,
                onCancelled: cancelMagnification,
                onPanBegan: beginTrackpadPan,
                onPanChanged: updateTrackpadPan,
                onPanEnded: endTrackpadPan,
                onPanCancelled: cancelTrackpadPan
            )
        }
        .gesture(selectionGesture.exclusively(before: emptySelectionGesture))
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
        .overlay(alignment: legendCorner.alignment) {
            if colourKeyVisible { nodeLegend }
        }
        .overlay(alignment: .trailing) {
            if let depthDragSession {
                DepthGuideView(
                    landing: depthDragSession.landing,
                    movesBranch: depthDragSession.nodeIDs.count > 1
                )
                .padding(.trailing, 18)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
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
        .focusable()
        .focused($canvasFocused)
        .focusEffectDisabled()
        .onKeyPress(.return) {
            guard let id = store.selection else { return .ignored }
            store.beginRenaming(id)
            return .handled
        }
        .onKeyPress(.tab) {
            store.addChild(to: store.selection)
            return .handled
        }
        .accessibilityRepresentation {
            AccessibilitySpaceRepresentation(store: store)
        }
    }

    private var selectionGesture: some Gesture {
        SpatialTapGesture(count: 1)
            .targetedToAnyEntity()
            .onEnded { value in
                canvasFocused = true
                store.select(nodeID(from: value.entity))
            }
    }

    private var renameGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .targetedToAnyEntity()
            .onEnded { value in
                canvasFocused = true
                if let id = nodeID(from: value.entity) { store.beginRenaming(id) }
            }
    }

    private var emptySelectionGesture: some Gesture {
        SpatialTapGesture(count: 1)
            .onEnded { _ in
                canvasFocused = true
                store.hover(nil)
                store.select(nil)
            }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .targetedToAnyEntity()
            .onChanged { value in
                canvasFocused = true
                guard let id = nodeID(from: value.entity), let node = store.map.node(id: id) else { return }
                let origin = dragOrigins[id] ?? node.position
                if dragOrigins[id] == nil {
                    store.beginInteraction()
                    dragSnapshots[id] = store.sceneSnapshot
                    if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                        let isolatesNode = NSApp.currentEvent?.modifierFlags.contains(.command) == true
                        let nodeIDs = isolatesNode
                            ? Set([id])
                            : store.map.descendants(of: id).union([id])
                        let origins = Dictionary(uniqueKeysWithValues: store.map.nodes.compactMap { candidate in
                            nodeIDs.contains(candidate.id) ? (candidate.id, candidate.attention) : nil
                        })
                        depthDragSession = DepthDragSession(
                            rootID: id,
                            nodeIDs: nodeIDs,
                            originAttentions: origins,
                            snapshot: store.sceneSnapshot,
                            landing: DepthManipulation.landing(for: node.attention)
                        )
                    }
                }
                dragOrigins[id] = origin

                if var session = depthDragSession, session.rootID == id {
                    let rawAttention = DepthManipulation.attention(
                        origin: session.originAttentions[id] ?? node.attention,
                        verticalTranslation: value.translation.height,
                        viewportHeight: canvasSize.height,
                        cameraDistance: store.cameraIntent.pose.distance
                    )
                    let landing = DepthManipulation.landing(for: rawAttention)
                    session.landing = landing
                    depthDragSession = session
                    let delta = landing.attention - (session.originAttentions[id] ?? node.attention)
                    let previewItems = session.snapshot.items.compactMap { item -> FocusSceneSnapshot.Item? in
                        guard session.nodeIDs.contains(item.id),
                              let original = session.originAttentions[item.id] else { return nil }
                        return previewItem(
                            item,
                            position: item.position,
                            attention: original + delta
                        )
                    }
                    renderer.previewDepthDrag(items: previewItems, snapshot: session.snapshot)
                    return
                }

                let dx = Double(value.translation.width / 115)
                let dy = Double(-value.translation.height / 115)
                if let entity = nodeEntity(from: value.entity),
                   let snapshot = dragSnapshots[id],
                   let base = snapshot.items.first(where: { $0.id == id }) {
                    renderer.previewNodeDrag(
                        entity: entity,
                        item: previewItem(
                            base,
                            position: SpatialPoint(x: origin.x + dx, y: origin.y + dy),
                            attention: node.attention
                        ),
                        snapshot: snapshot
                    )
                }
            }
            .onEnded { value in
                if let id = nodeID(from: value.entity), let origin = dragOrigins[id] {
                    let dx = Double(value.translation.width / 115)
                    let dy = Double(-value.translation.height / 115)
                    if let session = depthDragSession, session.rootID == id {
                        store.setBranchAttention(
                            rootID: id,
                            nodeIDs: session.nodeIDs,
                            originAttentions: session.originAttentions,
                            rootAttention: session.landing.attention
                        )
                    } else {
                        store.move(id, to: SpatialPoint(x: origin.x + dx, y: origin.y + dy))
                    }
                    dragOrigins[id] = nil
                    dragSnapshots[id] = nil
                    depthDragSession = nil
                }
                store.endInteraction()
            }
    }

    private var navigationGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                canvasFocused = true
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

    private func beginMagnification() {
        magnifyOrigin = store.cameraIntent.pose
        noteNavigationActivity(scheduleIdleReturn: false)
    }

    private func updateMagnification(factor: Double) {
        let origin = magnifyOrigin ?? store.cameraIntent.pose
        if magnifyOrigin == nil { beginMagnification() }
        renderer.previewCamera(
            pose: store.zoomCameraPose(by: factor, from: origin),
            reduceMotion: reduceMotion
        )
    }

    private func endMagnification(factor: Double) {
        if let origin = magnifyOrigin {
            store.setCameraPose(store.zoomCameraPose(by: factor, from: origin))
        }
        magnifyOrigin = nil
        noteNavigationActivity()
    }

    private func cancelMagnification() {
        if let origin = magnifyOrigin {
            renderer.previewCamera(pose: origin, reduceMotion: reduceMotion)
        }
        magnifyOrigin = nil
        noteNavigationActivity()
    }

    private func beginTrackpadPan() {
        trackpadPanOrigin = store.cameraIntent.pose
        noteNavigationActivity(scheduleIdleReturn: false)
    }

    private func updateTrackpadPan(translation: CGSize) {
        let origin = trackpadPanOrigin ?? store.cameraIntent.pose
        if trackpadPanOrigin == nil { beginTrackpadPan() }
        renderer.previewCamera(
            pose: store.panCameraPose(
                horizontal: translation.width,
                vertical: translation.height,
                from: origin
            ),
            reduceMotion: reduceMotion
        )
    }

    private func endTrackpadPan(translation: CGSize) {
        if let origin = trackpadPanOrigin {
            store.panCamera(
                horizontal: translation.width,
                vertical: translation.height,
                from: origin
            )
        }
        trackpadPanOrigin = nil
        noteNavigationActivity()
    }

    private func cancelTrackpadPan() {
        if let origin = trackpadPanOrigin {
            renderer.previewCamera(pose: origin, reduceMotion: reduceMotion)
        }
        trackpadPanOrigin = nil
        noteNavigationActivity()
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
                .help("Drag to orbit; use two fingers on the trackpad to pan")
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

    private var rendererTextScale: Float {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium, .large: 1
        case .xLarge: 1.06
        case .xxLarge: 1.10
        case .xxxLarge: 1.14
        default: 1.22
        }
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
            manualAttention: item.manualAttention,
            gravityReason: item.gravityReason,
            isGravityInfluenced: item.isGravityInfluenced,
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

private struct DepthDragSession {
    let rootID: UUID
    let nodeIDs: Set<UUID>
    let originAttentions: [UUID: Double]
    let snapshot: FocusSceneSnapshot
    var landing: DepthManipulation.Landing
}

private struct DepthGuideView: View {
    let landing: DepthManipulation.Landing
    let movesBranch: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(movesBranch ? "Moving branch" : "Moving in depth", systemImage: "move.3d")
                .font(.caption.weight(.semibold))
            GeometryReader { proxy in
                let height = proxy.size.height
                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(.white.opacity(0.16))
                        .frame(width: 2, height: height)
                        .offset(x: 7)
                    ForEach(AttentionBand.allCases) { band in
                        let y = (1 - band.attention) * height
                        HStack(spacing: 8) {
                            Circle()
                                .fill(landing.band == band ? Color.accentColor : .white.opacity(0.32))
                                .frame(width: landing.band == band ? 10 : 6, height: landing.band == band ? 10 : 6)
                            Text(band.displayName)
                                .foregroundStyle(landing.band == band ? .primary : .secondary)
                        }
                        .font(.caption2)
                        .position(x: 55, y: y)
                    }
                    Circle()
                        .fill(.white)
                        .shadow(color: .blue.opacity(0.8), radius: 7)
                        .frame(width: 9, height: 9)
                        .position(x: 8, y: (1 - landing.attention) * height)
                }
            }
            .frame(height: 205)
            Text(landing.band?.displayName ?? landing.attention.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption.weight(.medium))
                .foregroundStyle(landing.band == nil ? .secondary : .primary)
            Text("⌥ drag · ⌘⌥ isolates one item")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(width: 142)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 13))
        .overlay { RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.10)) }
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
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

struct WorkspaceBackground: View {
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
