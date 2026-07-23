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
                    .help("Choose what kind of thought this is; kind controls its colour and shape language")
                    Picker("Urgency", selection: Binding(
                        get: { store.selectedNode?.urgency ?? .none },
                        set: { store.setUrgency(node.id, to: $0) }
                    )) {
                        ForEach(FocusNodeUrgency.allCases) { urgency in
                            Text(urgency.displayName).tag(urgency)
                        }
                    }
                    .help("Mark time-sensitive work so it is visually distinguishable")
                    Toggle("Active", isOn: Binding(
                        get: { store.selectedNode?.isEnabled ?? true },
                        set: { store.setEnabled(node.id, to: $0) }
                    ))
                    .help("Inactive thoughts stay visible but are visually quiet")
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Notes")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: Binding(
                                get: { store.selectedNode?.notes ?? "" },
                                set: { store.setNotes(node.id, to: $0) }
                            ))
                            .font(.callout)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 3)
                            .focused($notesFocused)
                            .help("Add multi-line context; it appears when this thought is selected")
                            if node.notes.isEmpty {
                                Text("Add context that appears on the selected card…")
                                    .font(.callout)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 10)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: 92, maxHeight: 128)
                        .background(.black.opacity(0.16), in: .rect(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.10)) }
                    }
                    .onChange(of: notesFocused) { _, focused in
                        if focused { store.beginInteraction() } else { store.endInteraction() }
                    }
                    relationshipsSection(node)
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
                        .help("Move this thought to a named attention depth")
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
                        .help("Set how close this thought sits to you; closer means more attention")
                        Text(attentionDescription(node.attention))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    Button("Add child", systemImage: "arrow.turn.down.right") { store.addChild(to: node.id) }
                        .help("Add a child beneath this thought")
                    Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(node.id) }
                        .help("Create a copy beside this thought")
                    Button("Delete", systemImage: "trash", role: .destructive) { store.delete(node.id) }
                        .help("Delete this thought and its descendants")
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
    private func relationshipsSection(_ node: FocusNode) -> some View {
        let related = store.relatedNodes(for: node.id)
        let available = store.availableRelatedNodes(for: node.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Related thoughts", systemImage: "point.2.filled.connected.trianglepath.dotted")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Menu("Add relationship", systemImage: "link.badge.plus") {
                    if available.isEmpty {
                        Text("No other thoughts available")
                    } else {
                        ForEach(available) { candidate in
                            Button(candidate.title) {
                                store.addRelatedNode(candidate.id, to: node.id)
                            }
                        }
                    }
                }
                .labelStyle(.iconOnly)
                .menuStyle(.borderlessButton)
                .help("Create a dashed purple “related to” link without changing the hierarchy")
                .disabled(available.isEmpty)
            }
            if related.isEmpty {
                Text("No cross-links. Add one to connect ideas outside the parent–child hierarchy.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(related) { candidate in
                    HStack(spacing: 8) {
                        Button(candidate.title) {
                            store.select(candidate.id)
                        }
                        .buttonStyle(.link)
                        .lineLimit(1)
                        .help("Select \(candidate.title)")
                        Spacer()
                        Button("Remove relationship", systemImage: "xmark") {
                            store.removeRelatedNode(candidate.id, from: node.id)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Remove the related-thought link to \(candidate.title)")
                    }
                    .font(.caption)
                }
            }
            Text("Dashed purple lines mean “related to”; solid blue lines show parent and child.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
                .help("Choose whether time signals may suggest this thought’s depth")
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
                        .help("End the seven-day manual-depth hold and apply gravity immediately")
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
            .help(value == nil ? "Add a \(title.lowercased())" : "Remove this \(title.lowercased())")
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
                .help("Choose the \(title.lowercased())")
            }
        }
    }
}
