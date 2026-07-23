import AppKit
import SwiftUI

struct PersistenceDiagnosticsView: View {
    @ObservedObject var store: FocusSpaceStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Storage details", systemImage: "externaldrive.badge.checkmark")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .help("Close storage details")
            }

            if store.recoveredFromBackup {
                Label("This session recovered the last valid copy.", systemImage: "lifepreserver")
                    .foregroundStyle(.orange)
            } else {
                Label("The current space opened normally.", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }

            locationRow("Autosave location", url: store.storageLocations.primary)
            locationRow("Recovery copy", url: store.storageLocations.recovery)

            LabeledContent("Autosave") {
                Text(store.isPreviewingDemo
                    ? "Paused for experience previews"
                    : "350 ms after a change and when the app becomes inactive")
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Last saved") {
                Text(store.lastSavedAt?.formatted(date: .abbreviated, time: .standard) ?? "Not during this session")
            }

            HStack {
                Button("Save Now") { store.saveImmediately() }
                    .help("Write the current space to its autosave location now")
                Spacer()
                if let url = store.storageLocations.primary {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .help("Reveal the autosaved space in Finder")
                }
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    @ViewBuilder
    private func locationRow(_ title: String, url: URL?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(url?.path(percentEncoded: false) ?? "Unavailable for this storage provider")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(.black.opacity(0.14), in: .rect(cornerRadius: 7))
        }
    }
}
