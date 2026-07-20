import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: FocusSpaceStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("universeGuideOpacity") private var universeGuideOpacity = 0.08
    @AppStorage("nodeShapePreference") private var nodeShapePreferenceRaw = NodeShapePreference.semantic.rawValue
    @AppStorage("inspectorVisible") private var inspectorVisible = true
    @AppStorage("colourKeyVisible") private var colourKeyVisible = true
    @AppStorage("hasCompletedSpatialGuide") private var hasCompletedSpatialGuide = false
    @AppStorage("spatialLearningProgress") private var spatialLearningProgressRaw = 0
    @AppStorage("preferAccessibleList") private var preferAccessibleList = false
    @AppStorage("soundEffectsEnabled") private var soundEffectsEnabled = false
    @State private var spatialGuideVisible = false
    @State private var workspaceGuidesVisible = false
    @State private var importerVisible = false
    @State private var exporterVisible = false
    @State private var persistenceDiagnosticsVisible = false
    @State private var importInProgress = false
    @StateObject private var performanceMonitor = ReleasePerformanceMonitor()
    @StateObject private var soundPlayer = FocusSoundPlayer()

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            HStack(spacing: 0) {
                if usesListFallback {
                    FocusListFallbackView(store: store)
                } else {
                    FocusRealityView(
                        store: store,
                        universeGuideOpacity: $universeGuideOpacity,
                        colourKeyVisible: $colourKeyVisible,
                        nodeShapePreference: NodeShapePreference(rawValue: nodeShapePreferenceRaw) ?? .semantic
                    )
                }
                if inspectorVisible {
                    Divider()
                    NodeInspector(store: store)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) { searchField }
            .overlay(alignment: .bottomLeading) { contextualHint }
            .overlay { workspaceStateOverlay }
            .overlay(alignment: .topLeading) {
                if showsPerformanceHUD {
                    PerformanceHUD(monitor: performanceMonitor, store: store)
                        .padding(12)
                }
            }
        }
        .navigationTitle(store.map.title)
        .toolbar { toolbar }
        .sheet(item: editingBinding) { node in
            RenameView(node: node) { store.rename(node.id, to: $0) }
        }
        .alert("Focus Space", isPresented: persistenceAlert) {
            Button("Storage Details") {
                store.dismissPersistenceMessage()
                persistenceDiagnosticsVisible = true
            }
            Button("Dismiss", role: .cancel, action: store.dismissPersistenceMessage)
        } message: {
            Text(store.persistenceMessage ?? "")
        }
        .sheet(isPresented: $spatialGuideVisible) {
            SpatialGuideView {
                hasCompletedSpatialGuide = true
                spatialGuideVisible = false
            }
            .interactiveDismissDisabled()
        }
        .onAppear {
            if !hasCompletedSpatialGuide { spatialGuideVisible = true }
        }
        .onChange(of: store.interactionRevision) { _, _ in
            guard let interaction = store.latestInteraction else { return }
            var progress = SpatialLearningProgress(rawValue: spatialLearningProgressRaw)
            progress.record(interaction)
            spatialLearningProgressRaw = progress.rawValue
            if soundEffectsEnabled {
                switch interaction {
                case .selectedThought: soundPlayer.play(.selection)
                case .changedDepth: soundPlayer.play(.depth)
                case .navigatedUniverse: break
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.saveImmediately() }
        }
        .fileImporter(
            isPresented: $importerVisible,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                importInProgress = true
                Task { @MainActor in
                    await Task.yield()
                    defer { importInProgress = false }
                    do {
                        try store.importMapData(data)
                    } catch {
                        store.reportPersistenceError("Import failed: \(error.localizedDescription)")
                    }
                }
            } catch {
                store.reportPersistenceError("Import failed: \(error.localizedDescription)")
            }
        }
        .fileExporter(
            isPresented: $exporterVisible,
            document: FocusMapDocument(map: store.map),
            contentType: .json,
            defaultFilename: safeExportName
        ) { result in
            if case let .failure(error) = result {
                store.reportPersistenceError("Export failed: \(error.localizedDescription)")
            }
        }
        .sheet(isPresented: $persistenceDiagnosticsVisible) {
            PersistenceDiagnosticsView(store: store)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                store.refreshGravity()
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FOCUS SPACE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            ForEach(FocusSpaceStore.Filter.allCases) { filter in
                Button {
                    withAnimation(FocusMotion.calmSpring) { store.filter = filter }
                } label: {
                    Label(filter.rawValue, systemImage: icon(for: filter))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                        .background(store.filter == filter ? Color.accentColor.opacity(0.17) : .clear, in: .rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Universe web", systemImage: "circle.grid.3x3")
                    Spacer()
                    Text("\(Int((universeGuideOpacity * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                Slider(value: $universeGuideOpacity, in: 0...0.22, step: 0.02)
                    .accessibilityLabel("Universe web opacity")
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                Label("Node shape", systemImage: "rectangle.on.rectangle")
                    .font(.caption)
                Picker("Node shape", selection: $nodeShapePreferenceRaw) {
                    ForEach(NodeShapePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            Toggle(isOn: Binding(
                get: { store.map.isGravityEnabled },
                set: store.setGravityEnabled
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Gravity & time", systemImage: "clock.arrow.trianglehead.2.counterclockwise.rotate.90")
                    Text(store.map.isGravityEnabled ? "Time can suggest depth" : "Manual depth only")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            Spacer()
            Menu {
                Button("Personal space") { store.preview(nil) }
                Divider()
                ForEach(DemoScene.allCases) { scene in
                    Button {
                        withAnimation(FocusMotion.calmSpring) {
                            store.preview(scene)
                        }
                    } label: {
                        if store.demoScene == scene {
                            Label(scene.rawValue, systemImage: "checkmark")
                        } else {
                            Text(scene.rawValue)
                        }
                    }
                }
            } label: {
                Label(
                    store.demoScene?.rawValue ?? "Experience previews",
                    systemImage: "sparkles.rectangle.stack"
                )
                .font(.caption)
                .lineLimit(2)
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 12)
        }
        .frame(minWidth: 175)
        .background(.ultraThinMaterial)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button("Undo", systemImage: "arrow.uturn.backward", action: store.undo).disabled(!store.canUndo)
            Button("Redo", systemImage: "arrow.uturn.forward", action: store.redo).disabled(!store.canRedo)
            Button("Add thought", systemImage: "plus") { store.addChild(to: nil) }
            Button("Arrange mind map", systemImage: "wand.and.stars") { store.arrangeMindMap() }
                .disabled(!store.canArrange)
            Button("Search", systemImage: "magnifyingglass") {
                withAnimation(.spring(response: 0.35)) {
                    if store.isSearching {
                        store.updateSearchText("")
                        store.isSearching = false
                    } else {
                        store.isSearching = true
                    }
                }
            }
            Button("Workspace guides", systemImage: "rectangle.3.group") {
                workspaceGuidesVisible.toggle()
            }
            .popover(isPresented: $workspaceGuidesVisible, arrowEdge: .top) {
                WorkspaceGuidesView(
                    store: store,
                    colourKeyVisible: $colourKeyVisible,
                    preferAccessibleList: $preferAccessibleList,
                    soundEffectsEnabled: $soundEffectsEnabled
                )
            }
            Button("Spatial guide", systemImage: "questionmark.circle") {
                spatialGuideVisible = true
            }
            Menu("Space file", systemImage: "externaldrive") {
                Button("Import Space…", systemImage: "square.and.arrow.down") {
                    importerVisible = true
                }
                Button("Export Space…", systemImage: "square.and.arrow.up") {
                    exporterVisible = true
                }
                Divider()
                Button("Save Now", systemImage: "externaldrive.badge.checkmark") {
                    store.saveImmediately()
                }
                Button("Storage Details…", systemImage: "info.circle") {
                    persistenceDiagnosticsVisible = true
                }
            }
            if let id = store.selection {
                Button(
                    store.isFocusModeEnabled ? "Show all branches" : "Focus selected branch",
                    systemImage: store.isFocusModeEnabled ? "eye" : "scope"
                ) {
                withAnimation(FocusMotion.quickFade) { store.toggleFocusMode() }
                }
                Button("Pull forward", systemImage: "arrow.up.to.line") { store.shiftAttention(id, by: 0.12) }
                Button("Push back", systemImage: "arrow.down.to.line") { store.shiftAttention(id, by: -0.12) }
            }
            Button(inspectorVisible ? "Hide inspector" : "Show inspector", systemImage: "sidebar.right") {
                withAnimation(FocusMotion.quickSpring) {
                    inspectorVisible.toggle()
                }
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help(inspectorVisible ? "Hide inspector" : "Show inspector")
        }
    }

    @ViewBuilder
    private var searchField: some View {
        if store.isSearching {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find a thought", text: Binding(
                    get: { store.searchText },
                    set: store.updateSearchText
                ))
                    .textFieldStyle(.plain)
                if !store.searchText.isEmpty {
                    Text("\(store.searchResultCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button("Clear", systemImage: "xmark.circle.fill") {
                        store.updateSearchText("")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                }
                Button("Done") {
                    store.updateSearchText("")
                    store.isSearching = false
                }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(width: 320)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                .shadow(radius: 20)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var contextualHint: some View {
        if hasCompletedSpatialGuide,
           let hint = SpatialLearningProgress(rawValue: spatialLearningProgressRaw).nextHint {
            Label(hint, systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: .capsule)
                .padding(14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var workspaceStateOverlay: some View {
        if importInProgress || CommandLine.arguments.contains("--simulate-loading") {
            WorkspaceLoadingView()
        } else if store.map.nodes.isEmpty {
            EmptySpaceView(
                addFirstThought: { store.addChild(to: nil) },
                importSpace: { importerVisible = true }
            )
        }
    }

    private var editingBinding: Binding<FocusNode?> {
        Binding(
            get: { store.editingNodeID.flatMap(store.map.node(id:)) },
            set: { if $0 == nil { store.editingNodeID = nil } }
        )
    }

    private var persistenceAlert: Binding<Bool> {
        Binding(
            get: { store.persistenceMessage != nil },
            set: { if !$0 { store.dismissPersistenceMessage() } }
        )
    }

    private var safeExportName: String {
        let cleaned = store.map.title
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Focus Space" : cleaned
    }

    private var usesListFallback: Bool {
        WorkspaceRendererAvailability.usesListFallback(preference: preferAccessibleList)
    }

    private var showsPerformanceHUD: Bool {
        CommandLine.arguments.contains("--performance-hud")
    }

    private func icon(for filter: FocusSpaceStore.Filter) -> String {
        switch filter {
        case .today: "scope"
        case .all: "circle.grid.cross"
        case .parked: "mountain.2"
        }
    }
}

private struct RenameView: View {
    let node: FocusNode
    let commit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @FocusState private var focused: Bool

    init(node: FocusNode, commit: @escaping (String) -> Void) {
        self.node = node
        self.commit = commit
        _title = State(initialValue: node.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Rename thought").font(.headline)
            TextField("Name", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { completeRename() }
            HStack {
                Spacer()
                Button("Done", action: completeRename)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { focused = true }
    }

    private func completeRename() {
        commit(title)
        dismiss()
    }
}
