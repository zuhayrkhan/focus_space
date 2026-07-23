import SwiftUI

extension View {
    func focusHelp(_ title: String, shortcut: String? = nil) -> some View {
        modifier(FocusTooltipModifier(title: title, shortcut: shortcut))
    }
}

private struct FocusTooltipModifier: ViewModifier {
    let title: String
    let shortcut: String?
    @State private var isPresented = false
    @State private var presentationTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .accessibilityHint(accessibilityHelp)
            .onHover { hovering in
                presentationTask?.cancel()
                if hovering {
                    presentationTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        guard !Task.isCancelled else { return }
                        isPresented = true
                    }
                } else {
                    isPresented = false
                }
            }
            .popover(
                isPresented: $isPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                FocusTooltipBubble(title: title, shortcut: shortcut)
            }
            .onDisappear {
                presentationTask?.cancel()
                isPresented = false
            }
    }

    private var accessibilityHelp: String {
        guard let shortcut else { return title }
        return "\(title) (\(shortcut))"
    }
}

private struct FocusTooltipBubble: View {
    let title: String
    let shortcut: String?

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.12), in: .capsule)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: .rect(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(.primary.opacity(0.10))
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .padding(3)
    }
}
