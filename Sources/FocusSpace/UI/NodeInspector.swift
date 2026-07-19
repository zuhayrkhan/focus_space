import SwiftUI

struct NodeInspector: View {
    @ObservedObject var store: FocusSpaceStore
    @FocusState private var notesFocused: Bool

    var body: some View {
        Group {
            if let node = store.selectedNode {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(node.title)
                            .font(.title2.weight(.semibold))
                    Picker("Kind", selection: Binding(
                        get: { store.selectedNode?.kind ?? .task },
                        set: { store.setKind(node.id, to: $0) }
                    )) {
                        ForEach(FocusNodeKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    Picker("Urgency", selection: Binding(
                        get: { store.selectedNode?.urgency ?? .none },
                        set: { store.setUrgency(node.id, to: $0) }
                    )) {
                        ForEach(FocusNodeUrgency.allCases) { urgency in
                            Text(urgency.displayName).tag(urgency)
                        }
                    }
                    Toggle("Active", isOn: Binding(
                        get: { store.selectedNode?.isEnabled ?? true },
                        set: { store.setEnabled(node.id, to: $0) }
                    ))
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Notes")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ZStack(alignment: .topLeading) {
                            if node.notes.isEmpty {
                                Text("Add context that appears on the selected card…")
                                    .font(.callout)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 8)
                            }
                            TextEditor(text: Binding(
                                get: { store.selectedNode?.notes ?? "" },
                                set: { store.setNotes(node.id, to: $0) }
                            ))
                            .font(.callout)
                            .scrollContentBackground(.hidden)
                            .focused($notesFocused)
                        }
                        .frame(minHeight: 92, maxHeight: 128)
                        .padding(4)
                        .background(.black.opacity(0.16), in: .rect(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.10)) }
                    }
                    .onChange(of: notesFocused) { _, focused in
                        if focused { store.beginInteraction() } else { store.endInteraction() }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Attention")
                            Spacer()
                            Text(node.attention, format: .percent.precision(.fractionLength(0)))
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { store.selectedNode?.attention ?? 0 },
                                set: { store.setAttention(node.id, to: $0) }
                            ),
                            in: 0...1,
                            onEditingChanged: { editing in
                                if editing { store.beginInteraction() } else { store.endInteraction() }
                            }
                        )
                        .tint(.blue)
                        Text(attentionDescription(node.attention))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    Button("Add child", systemImage: "arrow.turn.down.right") { store.addChild(to: node.id) }
                    Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(node.id) }
                    Button("Delete", systemImage: "trash", role: .destructive) { store.delete(node.id) }
                    }
                    .padding(20)
                }
            } else {
                ContentUnavailableView(
                    "Nothing selected",
                    systemImage: "circle.dotted",
                    description: Text("Choose a thought in the space.")
                )
            }
        }
        .frame(width: 260)
        .background(.ultraThinMaterial)
    }

    private func attentionDescription(_ value: Double) -> String {
        switch value {
        case 0..<0.25: "Parked in the distance"
        case 0.25..<0.6: "Within reach"
        case 0.6..<0.85: "In active focus"
        default: "Closest to you"
        }
    }
}
