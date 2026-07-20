import SwiftUI

struct EmptySpaceView: View {
    let addFirstThought: () -> Void
    let importSpace: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.cyan.opacity(0.8))
            Text("A quiet space")
                .font(.title2.weight(.medium))
            Text("Begin with one thought. Its shape can grow from there.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Import a space", action: importSpace)
                Button("Add first thought", action: addFirstThought)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 30, y: 12)
        .accessibilityElement(children: .contain)
    }
}

struct WorkspaceLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Opening your space…")
                .font(.headline)
            Text("Restoring depth and relationships")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}
