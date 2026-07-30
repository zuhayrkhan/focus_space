import RealityKit
import SwiftUI

struct FocusRealityView: View {
    @ObservedObject var store: FocusSpaceStore
    @Binding var universeGuideOpacity: Double
    @Binding var colourKeyVisible: Bool
    @Binding var preferAccessibleList: Bool
    let nodeShapePreference: NodeShapePreference
    let workspaceChromeHidden: Bool
    @ObservedObject var performanceMonitor: ReleasePerformanceMonitor
    let onCanvasInteraction: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("nodeLegendCorner") private var legendCornerRaw = LegendCorner.topTrailing.rawValue
    @AppStorage("nodeLegendCornerIsManual") private var legendCornerIsManual = false
    @State private var renderer = RealityFocusRenderer()
    @State private var spatialDragSession: SpatialDragSession?
    @State private var depthDragSession: DepthDragSession?
    @State private var cameraDragOrigin: FocusCameraIntent.Pose?
    @State private var magnifyOrigin: FocusCameraIntent.Pose?
    @State private var trackpadPanOrigin: FocusCameraIntent.Pose?
    @State private var trackpadPanMode: TrackpadPanMode?
    @State private var selectionGuard = CanvasSelectionGuard()
    @State private var rotationOrigin: FocusCameraIntent.Pose?
    @State private var controlsVisible = true
    @State private var controlsTask: Task<Void, Never>?
    @State private var idleReturnTask: Task<Void, Never>?
    @State private var diagnosticPreviewTask: Task<Void, Never>?
    @State private var isLegendInteracting = false
    @State private var compactKeyIsExpanded = false
    @State private var navigationStartedOnLegend = false
    @State private var canvasSize = CGSize.zero
    @GestureState private var legendDragOffset = CGSize.zero
    @FocusState private var canvasFocused: Bool

    var body: some View {
        let snapshot = store.sceneSnapshot
        RealityView { content in
            content.add(renderer.makeScene())
        } update: { content in
            guard let root = content.entities.first?.findEntity(named: RealityFocusRenderer.rootName)
                ?? content.entities.first(where: { $0.name == RealityFocusRenderer.rootName }) else { return }
            renderer.reconcile(
                root: root,
                snapshot: snapshot,
                shapePreference: differentiateWithoutColor ? .semantic : nodeShapePreference,
                highContrast: colorSchemeContrast == .increased,
                textScale: rendererTextScale,
                reduceMotion: reduceMotion
            )
            renderer.updateAmbient(root: root, reduceMotion: reduceMotion)
            renderer.updateCamera(root: root, intent: store.cameraIntent, reduceMotion: reduceMotion)
            renderer.updateGuideOpacity(root: root, opacity: universeGuideOpacity)
            performanceMonitor.markWorkspaceReady()
            FocusPerformance.markLaunchInteractive()
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
        .overlay(alignment: effectiveLegendCorner.alignment) {
            colourKeyOverlay
        }
        .overlay(alignment: .trailing) {
            if let depthDragSession, !workspaceChromeHidden {
                DepthGuideView(
                    landing: depthDragSession.landing,
                    movesBranch: depthDragSession.nodeIDs.count > 1
                )
                .padding(.trailing, 18)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if controlsVisible && !workspaceChromeHidden {
                navigationControls
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            canvasSize = newSize
        }
        .onAppear { noteNavigationActivity() }
        .onDisappear {
            controlsTask?.cancel()
            idleReturnTask?.cancel()
            diagnosticPreviewTask?.cancel()
        }
        .onChange(of: performanceMonitor.exerciseRevision) { _, revision in
            guard revision > 0 else { return }
            diagnosticPreviewTask?.cancel()
            diagnosticPreviewTask = Task { @MainActor in
                await runDiagnosticPreview(snapshot: snapshot)
            }
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
            AccessibilitySpaceRepresentation(
                store: store,
                snapshot: snapshot,
                preferAccessibleList: $preferAccessibleList
            )
        }
    }

    private var selectionGesture: some Gesture {
        SpatialTapGesture(count: 1)
            .targetedToAnyEntity()
            .onEnded { value in
                canvasFocused = true
                onCanvasInteraction()
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
                guard selectionGuard.permitsDeselection(
                    at: ProcessInfo.processInfo.systemUptime
                ) else { return }
                canvasFocused = true
                onCanvasInteraction()
                store.hover(nil)
                store.select(nil)
            }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .targetedToAnyEntity()
            .onChanged { value in
                canvasFocused = true
                if spatialDragSession == nil { onCanvasInteraction() }
                guard let id = nodeID(from: value.entity), store.map.node(id: id) != nil else { return }
                if spatialDragSession == nil {
                    store.beginInteraction()
                    let movesConnectedComponent = NSApp.currentEvent?.modifierFlags.contains(.option) == true
                    let nodeIDs = movesConnectedComponent
                        ? store.map.connectedComponent(containing: id)
                        : Set([id])
                    spatialDragSession = SpatialDragSession(
                        rootID: id,
                        nodeIDs: nodeIDs,
                        originPositions: Dictionary(uniqueKeysWithValues: store.map.nodes.compactMap { candidate in
                            nodeIDs.contains(candidate.id) ? (candidate.id, candidate.position) : nil
                        }),
                        snapshot: store.sceneSnapshot
                    )
                }
                guard let session = spatialDragSession, session.rootID == id else { return }
                let dx = Double(value.translation.width / 115)
                let dy = Double(-value.translation.height / 115)
                let previewItems = session.snapshot.items.compactMap { item -> FocusSceneSnapshot.Item? in
                    guard session.nodeIDs.contains(item.id),
                          let origin = session.originPositions[item.id] else { return nil }
                    return previewItem(
                        item,
                        position: SpatialPoint(x: origin.x + dx, y: origin.y + dy),
                        attention: item.attention,
                        renderPosition: item.renderPosition.map {
                            SpatialPoint(x: $0.x + dx, y: $0.y + dy)
                        }
                    )
                }
                if session.nodeIDs.count > 1 {
                    FocusPerformance.measure(.optionDragPreview) {
                        renderer.previewNodeDrag(items: previewItems, snapshot: session.snapshot)
                    }
                } else {
                    renderer.previewNodeDrag(items: previewItems, snapshot: session.snapshot)
                }
            }
            .onEnded { value in
                if let id = nodeID(from: value.entity),
                   let session = spatialDragSession,
                   session.rootID == id {
                    let dx = Double(value.translation.width / 115)
                    let dy = Double(-value.translation.height / 115)
                    store.translate(
                        session.nodeIDs,
                        from: session.originPositions,
                        by: SpatialPoint(x: dx, y: dy)
                    )
                }
                spatialDragSession = nil
                store.endInteraction()
            }
    }

    private var navigationGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                canvasFocused = true
                if cameraDragOrigin == nil { onCanvasInteraction() }
                if cameraDragOrigin == nil,
                   effectiveLegendCorner.contains(value.startLocation, in: canvasSize) {
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
        selectionGuard.beginNavigation()
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
        selectionGuard.endNavigation(at: ProcessInfo.processInfo.systemUptime)
        noteNavigationActivity()
    }

    private func cancelMagnification() {
        if let origin = magnifyOrigin {
            renderer.previewCamera(pose: origin, reduceMotion: reduceMotion)
        }
        magnifyOrigin = nil
        selectionGuard.endNavigation(at: ProcessInfo.processInfo.systemUptime)
        noteNavigationActivity()
    }

    private func beginTrackpadPan() {
        selectionGuard.beginNavigation()
        trackpadPanOrigin = store.cameraIntent.pose
        trackpadPanMode = .pending(store.hoveredNodeID)
        noteNavigationActivity(scheduleIdleReturn: false)
    }

    private func updateTrackpadPan(translation: CGSize) {
        guard var mode = trackpadPanMode else {
            beginTrackpadPan()
            return updateTrackpadPan(translation: translation)
        }
        mode = mode.resolved(for: translation)
        trackpadPanMode = mode

        if case let .branchDepth(id) = mode {
            if depthDragSession == nil { beginTrackpadDepth(for: id) }
            if var session = depthDragSession {
                previewDepth(session: &session, verticalTranslation: -translation.height)
            }
            return
        }
        guard mode == .camera else { return }

        let origin = trackpadPanOrigin ?? store.cameraIntent.pose
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
        if case .camera = trackpadPanMode,
           let origin = trackpadPanOrigin {
            store.panCamera(
                horizontal: translation.width,
                vertical: translation.height,
                from: origin
            )
        } else if case .branchDepth = trackpadPanMode,
                  let session = depthDragSession {
            store.setBranchAttention(
                rootID: session.rootID,
                nodeIDs: session.nodeIDs,
                originAttentions: session.originAttentions,
                rootAttention: session.landing.attention
            )
            store.endInteraction()
        }
        trackpadPanOrigin = nil
        trackpadPanMode = nil
        depthDragSession = nil
        selectionGuard.endNavigation(at: ProcessInfo.processInfo.systemUptime)
        noteNavigationActivity()
    }

    private func cancelTrackpadPan() {
        if case .camera = trackpadPanMode,
           let origin = trackpadPanOrigin {
            renderer.previewCamera(pose: origin, reduceMotion: reduceMotion)
        } else if case .branchDepth = trackpadPanMode,
                  let session = depthDragSession {
            let originalItems = session.snapshot.items.filter { session.nodeIDs.contains($0.id) }
            renderer.previewDepthDrag(items: originalItems, snapshot: session.snapshot)
            store.endInteraction()
        }
        trackpadPanOrigin = nil
        trackpadPanMode = nil
        depthDragSession = nil
        selectionGuard.endNavigation(at: ProcessInfo.processInfo.systemUptime)
        noteNavigationActivity()
    }

    private func beginTrackpadDepth(for id: UUID) {
        guard let node = store.map.node(id: id) else { return }
        let nodeIDs = store.map.descendants(of: id).union([id])
        let origins = Dictionary(uniqueKeysWithValues: store.map.nodes.compactMap { candidate in
            nodeIDs.contains(candidate.id) ? (candidate.id, candidate.attention) : nil
        })
        store.beginInteraction()
        depthDragSession = DepthDragSession(
            rootID: id,
            nodeIDs: nodeIDs,
            originAttentions: origins,
            snapshot: store.sceneSnapshot,
            landing: DepthManipulation.landing(for: node.attention)
        )
    }

    private func previewDepth(session: inout DepthDragSession, verticalTranslation: Double) {
        let originalAttention = session.originAttentions[session.rootID] ?? session.landing.attention
        let rawAttention = DepthManipulation.attention(
            origin: originalAttention,
            verticalTranslation: verticalTranslation,
            viewportHeight: canvasSize.height,
            cameraDistance: store.cameraIntent.pose.distance
        )
        session.landing = DepthManipulation.landing(for: rawAttention)
        depthDragSession = session
        let delta = session.landing.attention - originalAttention
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
                .focusHelp("Drag to orbit; two-finger drag to pan, or move vertically over a thought to shift its branch in depth")
            Divider().frame(height: 22)
            Button("Zoom out", systemImage: "minus.magnifyingglass") {
                selectionGuard.suppressDeselection(at: ProcessInfo.processInfo.systemUptime)
                store.zoomCamera(by: 0.84, animated: true)
                noteNavigationActivity()
            }
            .labelStyle(.iconOnly)
            .focusHelp("Zoom out; you can also pinch", shortcut: "⌘−")
            Button("Zoom in", systemImage: "plus.magnifyingglass") {
                selectionGuard.suppressDeselection(at: ProcessInfo.processInfo.systemUptime)
                store.zoomCamera(by: 1.18, animated: true)
                noteNavigationActivity()
            }
            .labelStyle(.iconOnly)
            .focusHelp("Zoom in; you can also stretch", shortcut: "⌘+")
            Button("Frame branch", systemImage: "viewfinder") {
                selectionGuard.suppressDeselection(at: ProcessInfo.processInfo.systemUptime)
                store.frameSelection()
                noteNavigationActivity(scheduleIdleReturn: false)
            }
            .labelStyle(.iconOnly)
            .disabled(!store.canFrameSelection)
            .focusHelp("Frame the selected thought and its descendants")
            Button("Reset to canonical universe", systemImage: "arrow.counterclockwise") {
                selectionGuard.suppressDeselection(at: ProcessInfo.processInfo.systemUptime)
                store.resetCamera()
                noteNavigationActivity(scheduleIdleReturn: false)
            }
            .labelStyle(.iconOnly)
            .focusHelp("Reset to the canonical universe view", shortcut: "⌘0")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 13))
        .overlay { RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.10)) }
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
        .padding(.bottom, 12)
        .allowsHitTesting(controlsVisible && !workspaceChromeHidden)
        .accessibilityHidden(!controlsVisible || workspaceChromeHidden)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !selectionGuard.isNavigationActive {
                        selectionGuard.beginNavigation()
                    }
                }
                .onEnded { _ in
                    selectionGuard.endNavigation(at: ProcessInfo.processInfo.systemUptime)
                }
        )
        .onHover { hovering in
            if hovering { controlsVisible = true; controlsTask?.cancel() }
            else { noteNavigationActivity() }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: controlsVisible)
    }

    @ViewBuilder
    private var colourKeyOverlay: some View {
        switch WorkspaceChromePolicy.colourKeyPresentation(
            isEnabled: colourKeyVisible,
            nodeCount: store.map.nodes.count,
            workspaceLevel: store.workspacePresentationLevel,
            isDistractionFree: workspaceChromeHidden,
            compactKeyIsExpanded: compactKeyIsExpanded
        ) {
        case .hidden:
            EmptyView()
        case .button:
            Button("Show colour key", systemImage: "circle.grid.2x2") {
                compactKeyIsExpanded = true
            }
            .labelStyle(.iconOnly)
            .controlSize(.large)
            .padding(14)
            .background(.ultraThinMaterial, in: .circle)
            .overlay { Circle().stroke(.white.opacity(0.12)) }
            .shadow(color: .black.opacity(0.20), radius: 12, y: 6)
            .padding(.bottom, effectiveLegendCorner.isBottom ? 42 : 0)
            .focusHelp("Expand the colour key")
        case .expanded:
            nodeLegend
        }
    }

    private var nodeLegend: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "circle.grid.2x2")
                Text("COLOUR KEY")
                Spacer(minLength: 8)
                if store.workspacePresentationLevel == .atlas || store.map.nodes.count >= 48 {
                    Button("Collapse colour key", systemImage: "chevron.down") {
                        compactKeyIsExpanded = false
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
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
        .padding(.bottom, effectiveLegendCorner.isBottom ? 46 : 14)
        .offset(legendDragOffset)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in isLegendInteracting = true }
                .updating($legendDragOffset) { value, offset, _ in
                    offset = value.translation
                }
                .onEnded { value in
                    legendCornerRaw = effectiveLegendCorner
                        .moved(by: value.translation)
                        .rawValue
                    legendCornerIsManual = true
                    Task { @MainActor in
                        await Task.yield()
                        isLegendInteracting = false
                    }
                }
        )
        .focusHelp("Drag the colour key toward any corner to dock it there")
    }

    private var storedLegendCorner: LegendCorner {
        LegendCorner(rawValue: legendCornerRaw) ?? .topTrailing
    }

    private var effectiveLegendCorner: LegendCorner {
        legendCornerIsManual ? storedLegendCorner : clearestLegendCorner
    }

    private var clearestLegendCorner: LegendCorner {
        let visibleItems = store.sceneSnapshot.items.filter { $0.presentationLevel.isSpatiallyVisible }
        let preferredOrder: [LegendCorner] = [.topTrailing, .bottomTrailing, .bottomLeading, .topLeading]
        return preferredOrder.min { lhs, rhs in
            let lhsContextPenalty = lhs == .topLeading && store.viewContextTitle != nil ? 20.0 : 0
            let rhsContextPenalty = rhs == .topLeading && store.viewContextTitle != nil ? 20.0 : 0
            return lhs.occupancyScore(for: visibleItems) + lhsContextPenalty
                < rhs.occupancyScore(for: visibleItems) + rhsContextPenalty
        } ?? .topTrailing
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

    @MainActor
    private func runDiagnosticPreview(snapshot: FocusSceneSnapshot) async {
        guard let rootItem = snapshot.items.first(where: {
            $0.presentationLevel.isSpatiallyVisible
        }) else {
            performanceMonitor.completeDiagnosticPreview(frameCount: 0, elapsedSeconds: 0)
            return
        }
        let nodeIDs = store.map.connectedComponent(containing: rootItem.id)
        let originalPose = store.cameraIntent.pose
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let frameCount = 90
        for frame in 0..<frameCount {
            guard !Task.isCancelled else { return }
            let phase = Double(frame) / Double(frameCount - 1) * .pi * 2
            let dx = sin(phase) * 0.12
            let dy = cos(phase) * 0.05
            let items = snapshot.items.compactMap { item -> FocusSceneSnapshot.Item? in
                guard nodeIDs.contains(item.id) else { return nil }
                return previewItem(
                    item,
                    position: SpatialPoint(x: item.position.x + dx, y: item.position.y + dy),
                    attention: item.attention,
                    renderPosition: item.renderPosition.map {
                        SpatialPoint(x: $0.x + dx, y: $0.y + dy)
                    }
                )
            }
            FocusPerformance.measure(.optionDragPreview) {
                renderer.previewNodeDrag(items: items, snapshot: snapshot)
            }
            renderer.previewCamera(
                pose: FocusCameraIntent.Pose(
                    target: SpatialPoint(
                        x: originalPose.target.x + sin(phase) * 0.04,
                        y: originalPose.target.y + cos(phase) * 0.03
                    ),
                    targetAttention: originalPose.targetAttention,
                    yaw: originalPose.yaw,
                    pitch: originalPose.pitch,
                    distance: originalPose.distance
                ),
                reduceMotion: true
            )
            try? await Task.sleep(for: .milliseconds(8))
        }
        renderer.previewNodeDrag(
            items: snapshot.items.filter { nodeIDs.contains($0.id) },
            snapshot: snapshot
        )
        renderer.previewCamera(pose: originalPose, reduceMotion: true)
        let endedAt = DispatchTime.now().uptimeNanoseconds
        performanceMonitor.completeDiagnosticPreview(
            frameCount: frameCount,
            elapsedSeconds: Double(endedAt - startedAt) / 1_000_000_000
        )
    }

    private func nodeID(from entity: Entity) -> UUID? {
        nodeEntity(from: entity).flatMap { UUID(uuidString: String($0.name.dropFirst(5))) }
    }

    private func previewItem(
        _ item: FocusSceneSnapshot.Item,
        position: SpatialPoint,
        attention: Double,
        renderPosition: SpatialPoint? = nil
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
            contextRole: item.contextRole,
            presentationLevel: item.presentationLevel,
            renderPosition: renderPosition ?? item.renderPosition,
            presentationSummary: item.presentationSummary
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

private struct SpatialDragSession {
    let rootID: UUID
    let nodeIDs: Set<UUID>
    let originPositions: [UUID: SpatialPoint]
    let snapshot: FocusSceneSnapshot
}

enum TrackpadPanMode: Equatable {
    case pending(UUID?)
    case camera
    case branchDepth(UUID)

    func resolved(for translation: CGSize) -> Self {
        guard case let .pending(candidateID) = self else { return self }
        let horizontal = abs(translation.width)
        let vertical = abs(translation.height)
        guard max(horizontal, vertical) >= 3 else { return self }
        guard let candidateID, vertical > horizontal * 1.15 else { return .camera }
        return .branchDepth(candidateID)
    }
}

struct CanvasSelectionGuard: Equatable {
    static let navigationGraceInterval: TimeInterval = 0.8

    private(set) var isNavigationActive = false
    private(set) var lastNavigationEndedAt: TimeInterval?

    mutating func beginNavigation() {
        isNavigationActive = true
    }

    mutating func endNavigation(at timestamp: TimeInterval) {
        isNavigationActive = false
        lastNavigationEndedAt = timestamp
    }

    mutating func suppressDeselection(at timestamp: TimeInterval) {
        lastNavigationEndedAt = timestamp
    }

    func permitsDeselection(
        at timestamp: TimeInterval,
        graceInterval: TimeInterval = navigationGraceInterval
    ) -> Bool {
        guard !isNavigationActive else { return false }
        guard let lastNavigationEndedAt else { return true }
        return timestamp - lastNavigationEndedAt >= graceInterval
    }
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
            Text("Two-finger vertical drag")
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

private enum LegendCorner: String, CaseIterable {
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

    func occupancyScore(for items: [FocusSceneSnapshot.Item]) -> Double {
        items.reduce(0) { score, item in
            let position = item.renderPosition ?? item.position
            let horizontallyMatches = switch self {
            case .topLeading, .bottomLeading: position.x < 0
            case .topTrailing, .bottomTrailing: position.x >= 0
            }
            let verticallyMatches = switch self {
            case .topLeading, .topTrailing: position.y >= 0
            case .bottomLeading, .bottomTrailing: position.y < 0
            }
            guard horizontallyMatches, verticallyMatches else { return score }
            return score + (item.isSelected ? 8 : 1)
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
