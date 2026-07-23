import AppKit
import SwiftUI

struct NodeInspector: View {
    @ObservedObject var store: FocusSpaceStore

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
                    .focusHelp("Choose what kind of thought this is; kind controls its colour and shape language")
                    Picker("Urgency", selection: Binding(
                        get: { store.selectedNode?.urgency ?? .none },
                        set: { store.setUrgency(node.id, to: $0) }
                    )) {
                        ForEach(FocusNodeUrgency.allCases) { urgency in
                            Text(urgency.displayName).tag(urgency)
                        }
                    }
                    .focusHelp("Mark time-sensitive work so it is visually distinguishable")
                    Toggle("Active", isOn: Binding(
                        get: { store.selectedNode?.isEnabled ?? true },
                        set: { store.setEnabled(node.id, to: $0) }
                    ))
                    .focusHelp("Inactive thoughts stay visible but are visually quiet")
                    HStack(spacing: 8) {
                        Label(
                            node.placementPolicy == .automatic ? "Arranged automatically" : "Positioned by you",
                            systemImage: node.placementPolicy == .automatic ? "wand.and.stars" : "hand.draw"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Spacer()
                        if node.placementPolicy == .manual {
                            Button("Use automatic placement", systemImage: "arrow.uturn.backward.circle") {
                                store.useAutomaticPlacement(node.id)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .focusHelp("Let Focus Space place this thought automatically again")
                        }
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Notes")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ZStack(alignment: .topLeading) {
                            InsetNotesEditor(text: Binding(
                                get: { store.selectedNode?.notes ?? "" },
                                set: { store.setNotes(node.id, to: $0) }
                            )) { focused in
                                if focused { store.beginInteraction() } else { store.endInteraction() }
                            }
                            .focusHelp("Add multi-line context; it appears when this thought is selected")
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
                        .focusHelp("Move this thought to a named attention depth")
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
                        .focusHelp("Set how close this thought sits to you; closer means more attention")
                        Text(attentionDescription(node.attention))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    Button("Add child", systemImage: "arrow.turn.down.right") { store.addChild(to: node.id) }
                        .focusHelp("Add a child beneath this thought")
                    Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(node.id) }
                        .focusHelp("Create a copy beside this thought")
                    Button("Delete", systemImage: "trash", role: .destructive) { store.delete(node.id) }
                        .focusHelp("Delete this thought and its descendants")
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
                .focusHelp("Create a dashed purple “related to” link without changing the hierarchy")
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
                        .focusHelp("Select \(candidate.title)")
                        Spacer()
                        Button("Remove relationship", systemImage: "xmark") {
                            store.removeRelatedNode(candidate.id, from: node.id)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .focusHelp("Remove the related-thought link to \(candidate.title)")
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
                .focusHelp("Choose whether time signals may suggest this thought’s depth")
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
                        .focusHelp("End the seven-day manual-depth hold and apply gravity immediately")
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

private struct InsetNotesEditor: NSViewRepresentable {
    @Binding var text: String
    let onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 9, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        textView.setAccessibilityLabel("Notes")
        textView.setAccessibilityHelp("Add multi-line context; it appears when this thought is selected")
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else { return }
        let selectedRanges = textView.selectedRanges
        textView.string = text
        let validRanges = selectedRanges.filter {
            NSMaxRange($0.rangeValue) <= (text as NSString).length
        }
        if validRanges.isEmpty {
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        } else {
            textView.selectedRanges = validRanges
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InsetNotesEditor

        init(_ parent: InsetNotesEditor) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
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
            .focusHelp(value == nil ? "Add a \(title.lowercased())" : "Remove this \(title.lowercased())")
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
                .focusHelp("Choose the \(title.lowercased())")
            }
        }
    }
}
