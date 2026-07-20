import SwiftUI

struct AccessibilitySpaceRepresentation: View {
    @ObservedObject var store: FocusSpaceStore

    var body: some View {
        VStack {
            ForEach(store.sceneSnapshot.items) { item in
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

            ForEach(store.sceneSnapshot.relationships) { relationship in
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
