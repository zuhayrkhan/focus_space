import SwiftUI

struct ContentView: View {
    @ObservedObject var store: FocusSpaceStore
    @AppStorage("universeGuideOpacity") private var universeGuideOpacity = 0.08
    @AppStorage("nodeShapePreference") private var nodeShapePreferenceRaw = NodeShapePreference.semantic.rawValue

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            HStack(spacing: 0) {
                FocusRealityView(
                    store: store,
                    universeGuideOpacity: $universeGuideOpacity,
                    nodeShapePreference: NodeShapePreference(rawValue: nodeShapePreferenceRaw) ?? .semantic
                )
                if store.selection != nil { NodeInspector(store: store) }
            }
            .overlay(alignment: .top) { searchField }
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
        .onKeyPress(.return) {
            guard let id = store.selection else { return .ignored }
            store.beginRenaming(id)
            return .handled
        }
        .onKeyPress(.tab) {
            store.addChild(to: store.selection)
            return .handled
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
                withAnimation(.spring(response: 0.35)) { store.isSearching.toggle() }
            }
            if let id = store.selection {
                Button("Pull forward", systemImage: "arrow.up.to.line") { store.shiftAttention(id, by: 0.12) }
                Button("Push back", systemImage: "arrow.down.to.line") { store.shiftAttention(id, by: -0.12) }
            }
        }
    }

    @ViewBuilder
    private var searchField: some View {
        if store.isSearching {
            TextField("Find a thought", text: $store.searchText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(width: 320)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                .shadow(radius: 20)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
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
