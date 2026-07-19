import AppKit
import SwiftUI

struct TrackpadMagnificationBridge: NSViewRepresentable {
    let onBegan: () -> Void
    let onChanged: (Double) -> Void
    let onEnded: (Double) -> Void
    let onCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onBegan: onBegan,
            onChanged: onChanged,
            onEnded: onEnded,
            onCancelled: onCancelled
        )
    }

    func makeNSView(context: Context) -> MagnificationAttachmentView {
        let view = MagnificationAttachmentView()
        view.onWindowChanged = { [weak coordinator = context.coordinator] attachment in
            coordinator?.attach(to: attachment)
        }
        context.coordinator.attachmentView = view
        return view
    }

    func updateNSView(_ nsView: MagnificationAttachmentView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onCancelled = onCancelled
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: MagnificationAttachmentView, coordinator: Coordinator) {
        coordinator.detach()
    }

    static func scaleFactor(for magnification: Double) -> Double {
        min(max(1 + magnification, 0.25), 4)
    }

    @MainActor
    final class Coordinator: NSObject {
        var onBegan: () -> Void
        var onChanged: (Double) -> Void
        var onEnded: (Double) -> Void
        var onCancelled: () -> Void
        weak var attachmentView: MagnificationAttachmentView?
        private weak var hostWindow: NSWindow?
        private var eventMonitor: Any?
        private var accumulatedMagnification = 0.0
        private var isGestureActive = false

        var isMonitoring: Bool { eventMonitor != nil }

        init(
            onBegan: @escaping () -> Void,
            onChanged: @escaping (Double) -> Void,
            onEnded: @escaping (Double) -> Void,
            onCancelled: @escaping () -> Void
        ) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onCancelled = onCancelled
        }

        func attach(to attachment: MagnificationAttachmentView) {
            attachmentView = attachment
            guard let window = attachment.window,
                  hostWindow !== window else { return }
            detach()
            hostWindow = window
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
                self?.handleMagnification(event)
                return event
            }
        }

        func detach() {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            eventMonitor = nil
            hostWindow = nil
            accumulatedMagnification = 0
            isGestureActive = false
        }

        private func handleMagnification(_ event: NSEvent) {
            guard let attachmentView,
                  event.window === hostWindow,
                  attachmentView.bounds.contains(attachmentView.convert(event.locationInWindow, from: nil)) else { return }

            if event.phase.contains(.mayBegin) { return }

            if event.phase.contains(.cancelled) {
                if isGestureActive { onCancelled() }
                accumulatedMagnification = 0
                isGestureActive = false
                return
            }

            if event.phase.contains(.began) || !isGestureActive {
                accumulatedMagnification = 0
                isGestureActive = true
                onBegan()
            }

            accumulatedMagnification += Double(event.magnification)
            let factor = Self.scaleFactor(for: accumulatedMagnification)
            if event.phase.contains(.ended) {
                onEnded(factor)
                accumulatedMagnification = 0
                isGestureActive = false
            } else {
                onChanged(factor)
            }
        }

        private static func scaleFactor(for magnification: Double) -> Double {
            TrackpadMagnificationBridge.scaleFactor(for: magnification)
        }
    }
}

final class MagnificationAttachmentView: NSView {
    var onWindowChanged: ((MagnificationAttachmentView) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?(self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
