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
                    gravitySection(node)
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Depth stop", selection: Binding<AttentionBand?>(
                            get: {
                                AttentionBand.allCases.first {
                                    abs($0.attention - (store.selectedNode?.attention ?? 0)) < 0.001
                                }
                            },
                            set: { band in
                                if let band { store.setAttention(node.id, to: band.attention) }
                            }
                        )) {
                            Text("Custom").tag(AttentionBand?.none)
                            ForEach(AttentionBand.allCases) { band in
                                Text(band.displayName).tag(Optional(band))
                            }
                        }
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

    @ViewBuilder
    private func gravitySection(_ node: FocusNode) -> some View {
        let assessment = store.gravityAssessment(for: node)
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Gravity", selection: Binding(
                    get: { store.selectedNode?.gravityPreference ?? .inherit },
                    set: { store.setGravityPreference(node.id, to: $0) }
                )) {
                    ForEach(GravityPreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                OptionalDateRow(
                    title: "Due date",
                    value: Binding(
                        get: { store.selectedNode?.dueDate },
                        set: { store.setDueDate(node.id, to: $0) }
                    ),
                    defaultOffset: 7 * 86_400
                )
                OptionalDateRow(
                    title: "Milestone",
                    value: Binding(
                        get: { store.selectedNode?.milestoneDate },
                        set: { store.setMilestoneDate(node.id, to: $0) }
                    ),
                    defaultOffset: 14 * 86_400
                )
                OptionalDateRow(
                    title: "Reminder",
                    value: Binding(
                        get: { store.selectedNode?.reminderDate },
                        set: { store.setReminderDate(node.id, to: $0) }
                    ),
                    defaultOffset: 86_400
                )
                VStack(alignment: .leading, spacing: 5) {
                    if assessment.isInfluencing {
                        Label(
                            "Gravity suggests \(assessment.attention.formatted(.percent.precision(.fractionLength(0))))",
                            systemImage: "arrow.up.forward"
                        )
                        .foregroundStyle(.cyan)
                    }
                    Text(assessment.reason)
                        .foregroundStyle(.secondary)
                    if node.lastManualOverride != nil,
                       assessment.reason.hasPrefix("Manual attention holds") {
                        Button("Let gravity resume now") {
                            store.releaseManualGravityOverride(node.id)
                        }
                        .buttonStyle(.link)
                    }
                }
                .font(.caption)
            }
            .padding(.top, 8)
        } label: {
            Label("Gravity & time", systemImage: assessment.isInfluencing ? "clock.badge.exclamationmark" : "clock")
                .font(.callout.weight(.semibold))
        }
    }
}

private struct OptionalDateRow: View {
    let title: String
    @Binding var value: Date?
    let defaultOffset: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(title, isOn: Binding(
                get: { value != nil },
                set: { enabled in
                    value = enabled ? Date.now.addingTimeInterval(defaultOffset) : nil
                }
            ))
            if value != nil {
                DatePicker(
                    title,
                    selection: Binding(
                        get: { value ?? Date.now },
                        set: { value = $0 }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
            }
        }
    }
}
