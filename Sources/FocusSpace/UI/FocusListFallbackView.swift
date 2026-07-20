import SwiftUI

struct FocusListFallbackView: View {
    @ObservedObject var store: FocusSpaceStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Accessible map view", systemImage: "list.bullet.indent")
                        .font(.headline)
                    Text("The same hierarchy and attention model without 3D effects.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Depth remains attention")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(orderedItems) { item in
                            row(item)
                                .id(item.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: store.selection) { _, selection in
                    guard let selection else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(selection, anchor: .center) }
                }
            }
        }
        .background(WorkspaceBackground())
    }

    private var orderedItems: [FocusSceneSnapshot.Item] {
        store.sceneSnapshot.items.sorted {
            if $0.hierarchyDepth != $1.hierarchyDepth { return $0.hierarchyDepth < $1.hierarchyDepth }
            if $0.position.y != $1.position.y { return $0.position.y > $1.position.y }
            return $0.position.x < $1.position.x
        }
    }

    private func row(_ item: FocusSceneSnapshot.Item) -> some View {
        let descriptor = FocusAccessibilityDescriptor.node(item, in: store.map)
        return Button {
            store.select(item.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: glyph(for: item.kind))
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.body.weight(store.selection == item.id ? .semibold : .regular))
                    Text(descriptor.value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(item.attention, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                    Text(AttentionBand.nearest(to: item.attention).displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if item.urgency != .none {
                    Image(systemName: item.urgency == .overdue ? "exclamationmark" : "clock")
                        .accessibilityLabel(item.urgency.displayName)
                }
            }
            .padding(.leading, CGFloat(item.hierarchyDepth) * 22)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                store.selection == item.id ? Color.accentColor.opacity(0.16) : .white.opacity(item.isDimmed ? 0.025 : 0.055),
                in: .rect(cornerRadius: 10)
            )
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(store.selection == item.id ? 0.24 : 0.07)) }
            .opacity(item.isDimmed ? 0.52 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(descriptor.label)
        .accessibilityValue(descriptor.value)
        .accessibilityHint(descriptor.hint)
        .accessibilityAddTraits(store.selection == item.id ? .isSelected : [])
        .contextMenu {
            Button("Pull Forward") { store.shiftAttention(item.id, by: 0.12) }
            Button("Push Back") { store.shiftAttention(item.id, by: -0.12) }
            Button("Add Child") { store.addChild(to: item.id) }
        }
    }

    private func glyph(for kind: FocusNodeKind) -> String {
        switch kind {
        case .project: "square.stack.3d.up"
        case .group: "circle.hexagongrid"
        case .task: "checkmark.circle"
        case .reference: "note.text"
        case .someday: "moon.stars"
        }
    }
}
