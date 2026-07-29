import SwiftUI

struct AccessibilitySpaceRepresentation: View {
    @ObservedObject var store: FocusSpaceStore
    let snapshot: FocusSceneSnapshot
    @Binding var preferAccessibleList: Bool

    var body: some View {
        let projection = FocusPerformance.measure(.accessibilityRepresentation) {
            AccessibilitySceneProjection.make(
                snapshot: snapshot,
                map: store.map,
                selection: store.selection
            )
        }
        VStack {
            if projection.omittedItemCount > 0 {
                Button("Open complete searchable thought list") {
                    preferAccessibleList = true
                }
                .accessibilityLabel("Open complete searchable thought list")
                .accessibilityValue(
                    "\(projection.omittedItemCount) off-context thoughts are available in the complete list"
                )
                .accessibilityHint("Switches from the spatial context to a complete hierarchical list")
            }

            ForEach(projection.items) { item in
                let descriptor = FocusAccessibilityDescriptor.node(item, in: store.map)
                Button(descriptor.label) { store.select(item.id) }
                    .accessibilityLabel(descriptor.label)
                    .accessibilityValue(descriptor.value)
                    .accessibilityHint(descriptor.hint)
                    .accessibilityAddTraits(store.selection == item.id ? .isSelected : [])
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: store.shiftAttention(item.id, by: 0.08)
                        case .decrement: store.shiftAttention(item.id, by: -0.08)
                        @unknown default: break
                        }
                    }
                    .accessibilityAction(named: Text("Pull forward")) {
                        store.shiftAttention(item.id, by: 0.12)
                    }
                    .accessibilityAction(named: Text("Push back")) {
                        store.shiftAttention(item.id, by: -0.12)
                    }
                    .accessibilityAction(named: Text("Add child")) {
                        store.addChild(to: item.id)
                    }
            }

            ForEach(projection.relationships) { relationship in
                if let descriptor = FocusAccessibilityDescriptor.relationship(relationship, in: store.map) {
                    Text(descriptor.label)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(descriptor.label)
                        .accessibilityValue(descriptor.value)
                        .accessibilityHint(descriptor.hint)
                }
            }
        }
    }
}
