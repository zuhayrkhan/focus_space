import SwiftUI

struct ContentView: View {
    @ObservedObject var store: FocusSpaceStore
    @AppStorage("universeGuideOpacity") private var universeGuideOpacity = 0.08
    @AppStorage("nodeShapePreference") private var nodeShapePreferenceRaw = NodeShapePreference.semantic.rawValue
    @AppStorage("inspectorVisible") private var inspectorVisible = true
    @AppStorage("colourKeyVisible") private var colourKeyVisible = true
    @AppStorage("hasCompletedSpatialGuide") private var hasCompletedSpatialGuide = false
    @AppStorage("spatialLearningProgress") private var spatialLearningProgressRaw = 0
    @State private var spatialGuideVisible = false
    @State private var workspaceGuidesVisible = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            HStack(spacing: 0) {
                FocusRealityView(
                    store: store,
                    universeGuideOpacity: $universeGuideOpacity,
                    colourKeyVisible: $colourKeyVisible,
                    nodeShapePreference: NodeShapePreference(rawValue: nodeShapePreferenceRaw) ?? .semantic
                )
                if inspectorVisible {
                    Divider()
                    NodeInspector(store: store)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) { searchField }
            .overlay(alignment: .bottomLeading) { contextualHint }
        }
        .navigationTitle(store.map.title)
        .toolbar { toolbar }
        .sheet(item: editingBinding) { node in
            RenameView(node: node) { store.rename(node.id, to: $0) }
        }
        .alert("Focus Space", isPresented: persistenceAlert) {
            Button("OK") {}
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
        }
        .onKeyPress(.return) {
            guard let id = store.selection else { return .ignored }
            store.beginRenaming(id)
            return .handled
        }
        .onKeyPress(.tab) {
            store.addChild(to: store.selection)
            return .handled
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
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { store.filter = filter }
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
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
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
            Text("Depth is attention")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(12)
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
                    colourKeyVisible: $colourKeyVisible
                )
            }
            Button("Spatial guide", systemImage: "questionmark.circle") {
                spatialGuideVisible = true
            }
            if let id = store.selection {
                Button(
                    store.isFocusModeEnabled ? "Show all branches" : "Focus selected branch",
                    systemImage: store.isFocusModeEnabled ? "eye" : "scope"
                ) {
                    withAnimation(.easeInOut(duration: 0.25)) { store.toggleFocusMode() }
                }
                Button("Pull forward", systemImage: "arrow.up.to.line") { store.shiftAttention(id, by: 0.12) }
                Button("Push back", systemImage: "arrow.down.to.line") { store.shiftAttention(id, by: -0.12) }
            }
            Button(inspectorVisible ? "Hide inspector" : "Show inspector", systemImage: "sidebar.right") {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
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

    private var editingBinding: Binding<FocusNode?> {
        Binding(
            get: { store.editingNodeID.flatMap(store.map.node(id:)) },
            set: { if $0 == nil { store.editingNodeID = nil } }
        )
    }

    private var persistenceAlert: Binding<Bool> {
        Binding(get: { store.persistenceMessage != nil }, set: { _ in })
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
                .onSubmit { commit(title) }
            HStack {
                Spacer()
                Button("Done") { commit(title) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { focused = true }
    }
}
