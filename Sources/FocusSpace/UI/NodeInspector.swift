import SwiftUI

struct NodeInspector: View {
    @ObservedObject var store: FocusSpaceStore

    var body: some View {
        Group {
            if let node = store.selectedNode {
                VStack(alignment: .leading, spacing: 18) {
                    Text(node.title)
                        .font(.title2.weight(.semibold))
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
                    Spacer()
                }
                .padding(20)
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
