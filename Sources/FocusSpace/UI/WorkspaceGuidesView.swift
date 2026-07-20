import SwiftUI

struct WorkspaceGuidesView: View {
    @ObservedObject var store: FocusSpaceStore
    @Binding var colourKeyVisible: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Workspace guides")
                    .font(.headline)
                Text("Open only what helps; the universe stays clear when this closes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisclosureGroup("Legend") {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(FocusNodeKind.allCases) { kind in
                            Label(kind.displayName, systemImage: glyph(for: kind))
                        }
                        Toggle("Floating colour key", isOn: $colourKeyVisible)
                            .padding(.top, 4)
                    }
                    .font(.caption)
                    .padding(.top, 8)
                }

                DisclosureGroup("Depth scale") {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(AttentionBand.allCases) { band in
                            HStack {
                                Circle()
                                    .fill(.white.opacity(0.25 + band.attention * 0.65))
                                    .frame(width: 7 + band.attention * 4, height: 7 + band.attention * 4)
                                Text(band.displayName)
                                Spacer()
                                Text(band.attention, format: .percent.precision(.fractionLength(0)))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.caption)
                    .padding(.top, 8)
                }

                DisclosureGroup("View filter") {
                    Picker("View filter", selection: $store.filter) {
                        ForEach(FocusSpaceStore.Filter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .padding(.top, 8)
                }

                DisclosureGroup("Time flow") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Due dates, milestones, and fired reminders can suggest that work comes closer. Manual depth always wins for seven days.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("Allow workspace gravity", isOn: Binding(
                            get: { store.map.isGravityEnabled },
                            set: store.setGravityEnabled
                        ))
                    }
                    .padding(.top, 8)
                }
            }
            .padding(18)
        }
        .frame(width: 310, height: 430)
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
