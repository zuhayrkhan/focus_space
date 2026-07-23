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
    @FocusState private var searchFocused: Bool

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
                        nodeShapePreference: NodeShapePreference(rawValue: nodeShapePreferenceRaw) ?? .semantic,
                        onCanvasInteraction: { workspaceGuidesVisible = false }
                    )
                }
                if inspectorVisible {
                    Divider()
                    NodeInspector(store: store)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) { searchField }
            .overlay(alignment: .topLeading) { viewContextBar }
            .overlay(alignment: .bottomLeading) { bottomMessages }
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
            SpatialGuideView(
                finish: {
                    hasCompletedSpatialGuide = true
                    spatialGuideVisible = false
                },
                dismiss: { spatialGuideVisible = false }
            )
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
        .onChange(of: store.selection) { _, _ in
            workspaceGuidesVisible = false
        }
        .onChange(of: store.isSearching) { _, searching in
            if searching {
                workspaceGuidesVisible = false
                Task { @MainActor in
                    await Task.yield()
                    searchFocused = true
                }
            } else {
                searchFocused = false
            }
        }
        .onChange(of: store.searchRequestRevision) { _, _ in
            workspaceGuidesVisible = false
            spatialGuideVisible = false
            Task { @MainActor in
                await Task.yield()
                searchFocused = true
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
        .onExitCommand { _ = dismissTransientUI() }
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
                    withAnimation(FocusMotion.calmSpring) { store.setFilter(filter) }
                } label: {
                    HStack {
                        Label(filter.rawValue, systemImage: icon(for: filter))
                        Spacer()
                        Text("\(store.filterCount(for: filter))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                        .background(store.filter == filter ? Color.accentColor.opacity(0.17) : .clear, in: .rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .focusHelp(filterHelp(filter))
            }
            if store.hiddenNodeCount > 0 {
                Text(hiddenThoughtsSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .accessibilityLabel("\(hiddenThoughtsSummary) filter")
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
                    .focusHelp("Adjust the opacity of the depth guide behind every thought")
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
                .focusHelp("Choose one shape language for thoughts throughout the space")
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
            .focusHelp("Allow dates, milestones, and reminders to suggest attention depth")
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
            .focusHelp("Open a deterministic example space, or return to your personal space")
            .padding(.horizontal, 12)
        }
        .frame(minWidth: 175)
        .background(.ultraThinMaterial)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button("Undo", systemImage: "arrow.uturn.backward", action: store.undo)
                .disabled(!store.canUndo)
                .focusHelp("Undo the last change", shortcut: "⌘Z")
            Button("Redo", systemImage: "arrow.uturn.forward", action: store.redo)
                .disabled(!store.canRedo)
                .focusHelp("Redo the last undone change", shortcut: "⇧⌘Z")
            Button("Add thought", systemImage: "plus") { store.addChild(to: nil) }
                .focusHelp("Add a new top-level thought")
            Button("Arrange mind map", systemImage: "wand.and.stars") { store.arrangeMindMap() }
                .disabled(!store.canArrange)
                .focusHelp("Clean up overlaps and arrange the current mind map")
            Button("Search", systemImage: "magnifyingglass") {
                withAnimation(.spring(response: 0.35)) {
                    if store.isSearching {
                        store.cancelSearch()
                    } else {
                        workspaceGuidesVisible = false
                        store.requestSearch()
                    }
                }
            }
            .focusHelp(
                store.isSearching ? "Close Find" : "Find a thought",
                shortcut: store.isSearching ? nil : "⌘F"
            )
            if store.islandSummaries.count > 1 {
                Menu("Islands", systemImage: "point.3.connected.trianglepath.dotted") {
                    Text("\(store.workspacePresentationLevel.rawValue.capitalized) view")
                    Divider()
                    ForEach(store.islandSummaries) { island in
                        Button {
                            store.frameIsland(island.rootID)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(island.title)
                                Text("\(island.thoughtCount) thoughts")
                            }
                        }
                    }
                }
                .focusHelp("Jump directly to a hierarchy island")
            }
            Button("Workspace guides", systemImage: "rectangle.3.group") {
                if !workspaceGuidesVisible {
                    store.cancelSearch()
                    spatialGuideVisible = false
                }
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
            .focusHelp("Show workspace legend, filters, gravity, and accessibility settings")
            Button("Spatial guide", systemImage: "questionmark.circle") {
                workspaceGuidesVisible = false
                store.cancelSearch()
                spatialGuideVisible = true
            }
            .focusHelp("Open the guide to depth, hierarchy, branch movement, and gravity")
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
            .focusHelp("Import, export, save, or inspect this space’s storage")
            if let id = store.selection {
                Button(
                    store.isFocusModeEnabled ? "Show all branches" : "Focus selected branch",
                    systemImage: store.isFocusModeEnabled ? "eye" : "scope"
                ) {
                withAnimation(FocusMotion.quickFade) { store.toggleFocusMode() }
                }
                .focusHelp(store.isFocusModeEnabled ? "Reveal every branch" : "Quiet unrelated branches and concentrate on the selection")
                Button("Pull forward", systemImage: "arrow.up.to.line") { store.shiftAttention(id, by: 0.12) }
                    .focusHelp("Pull the selected thought closer to increase its attention")
                Button("Push back", systemImage: "arrow.down.to.line") { store.shiftAttention(id, by: -0.12) }
                    .focusHelp("Push the selected thought away to decrease its attention")
            }
            Button(inspectorVisible ? "Hide inspector" : "Show inspector", systemImage: "sidebar.right") {
                withAnimation(FocusMotion.quickSpring) {
                    inspectorVisible.toggle()
                }
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .focusHelp(
                inspectorVisible ? "Hide inspector" : "Show inspector",
                shortcut: "⌥⌘I"
            )
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
                    .focused($searchFocused)
                    .onSubmit { store.commitSearchResult() }
                    .onKeyPress(.upArrow) {
                        store.selectSearchResult(by: -1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        store.selectSearchResult(by: 1)
                        return .handled
                    }
                    .focusHelp("Type part of a thought’s title or notes, then use Return to keep the result")
                if !store.searchText.isEmpty {
                    Text(searchResultSummary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(store.searchResultCount == 0 ? .orange : .secondary)
                    if store.searchResultCount > 1 {
                        Button("Previous result", systemImage: "chevron.up") {
                            store.selectSearchResult(by: -1)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .focusHelp("Select the previous result", shortcut: "↑")
                        Button("Next result", systemImage: "chevron.down") {
                            store.selectSearchResult(by: 1)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .focusHelp("Select the next result", shortcut: "↓")
                    }
                    Button("Clear", systemImage: "xmark.circle.fill") {
                        store.clearSearchQuery()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .focusHelp("Clear the search text")
                }
                Button("Cancel") { store.cancelSearch() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .focusHelp("Close Find and restore the previous view", shortcut: "Esc")
            }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(width: 430)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                .shadow(radius: 20)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var viewContextBar: some View {
        if let title = store.viewContextTitle, !store.isSearching {
            HStack(spacing: 8) {
                Label(title, systemImage: "scope")
                    .lineLimit(1)
                Divider().frame(height: 14)
                if store.canReturnFromViewContext {
                    Button(store.viewContextReturnTitle) { store.returnFromViewContext() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.cyan)
                        .focusHelp("Return to the view you had before entering this branch")
                } else {
                    Text("Choose an island")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: .capsule)
            .padding(12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var bottomMessages: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notice = store.visibilityNotice {
                HStack(spacing: 10) {
                    Label(notice.message, systemImage: "eye.slash")
                    Button("Show Everything") { store.showAllThoughts() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .focusHelp("Change the filter so every thought is visible")
                    Button("Dismiss", systemImage: "xmark") { store.dismissVisibilityNotice() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .focusHelp("Dismiss this notice")
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: .capsule)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            contextualHint
        }
        .padding(14)
    }

    private func filterHelp(_ filter: FocusSpaceStore.Filter) -> String {
        switch filter {
        case .today: "Show thoughts currently near enough to deserve attention"
        case .all: "Show every thought in the space"
        case .parked: "Show only thoughts intentionally pushed into the distance"
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

    private var searchResultSummary: String {
        guard store.searchResultCount > 0 else { return "No matches" }
        guard let position = store.searchResultPosition else {
            return "\(store.searchResultCount) matches"
        }
        return "\(position) of \(store.searchResultCount)"
    }

    private var hiddenThoughtsSummary: String {
        let noun = store.hiddenNodeCount == 1 ? "thought" : "thoughts"
        return "\(store.hiddenNodeCount) \(noun) hidden by \(store.filter.rawValue)"
    }

    @discardableResult
    private func dismissTransientUI() -> Bool {
        if spatialGuideVisible {
            spatialGuideVisible = false
            return true
        }
        if workspaceGuidesVisible {
            workspaceGuidesVisible = false
            return true
        }
        if store.isSearching {
            store.cancelSearch()
            return true
        }
        if store.selection != nil {
            store.select(nil)
            return true
        }
        return false
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
                .focusHelp("Enter the thought’s new name", shortcut: "↩")
            HStack {
                Spacer()
                Button("Done", action: completeRename)
                    .keyboardShortcut(.defaultAction)
                    .focusHelp("Save the new name and close", shortcut: "↩")
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
