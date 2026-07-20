import AppKit
import SwiftUI

struct TrackpadMagnificationBridge: NSViewRepresentable {
    let onBegan: () -> Void
    let onChanged: (Double) -> Void
    let onEnded: (Double) -> Void
    let onCancelled: () -> Void
    let onPanBegan: () -> Void
    let onPanChanged: (CGSize) -> Void
    let onPanEnded: (CGSize) -> Void
    let onPanCancelled: () -> Void

    init(
        onBegan: @escaping () -> Void,
        onChanged: @escaping (Double) -> Void,
        onEnded: @escaping (Double) -> Void,
        onCancelled: @escaping () -> Void,
        onPanBegan: @escaping () -> Void = {},
        onPanChanged: @escaping (CGSize) -> Void = { _ in },
        onPanEnded: @escaping (CGSize) -> Void = { _ in },
        onPanCancelled: @escaping () -> Void = {}
    ) {
        self.onBegan = onBegan
        self.onChanged = onChanged
        self.onEnded = onEnded
        self.onCancelled = onCancelled
        self.onPanBegan = onPanBegan
        self.onPanChanged = onPanChanged
        self.onPanEnded = onPanEnded
        self.onPanCancelled = onPanCancelled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onBegan: onBegan,
            onChanged: onChanged,
            onEnded: onEnded,
            onCancelled: onCancelled,
            onPanBegan: onPanBegan,
            onPanChanged: onPanChanged,
            onPanEnded: onPanEnded,
            onPanCancelled: onPanCancelled
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
        context.coordinator.onPanBegan = onPanBegan
        context.coordinator.onPanChanged = onPanChanged
        context.coordinator.onPanEnded = onPanEnded
        context.coordinator.onPanCancelled = onPanCancelled
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
        var onPanBegan: () -> Void
        var onPanChanged: (CGSize) -> Void
        var onPanEnded: (CGSize) -> Void
        var onPanCancelled: () -> Void
        weak var attachmentView: MagnificationAttachmentView?
        private weak var hostWindow: NSWindow?
        private var eventMonitor: Any?
        private var accumulatedMagnification = 0.0
        private var accumulatedPan = CGSize.zero
        private var isMagnificationActive = false
        private var isPanActive = false

        var isMonitoring: Bool { eventMonitor != nil }

        init(
            onBegan: @escaping () -> Void,
            onChanged: @escaping (Double) -> Void,
            onEnded: @escaping (Double) -> Void,
            onCancelled: @escaping () -> Void,
            onPanBegan: @escaping () -> Void,
            onPanChanged: @escaping (CGSize) -> Void,
            onPanEnded: @escaping (CGSize) -> Void,
            onPanCancelled: @escaping () -> Void
        ) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onCancelled = onCancelled
            self.onPanBegan = onPanBegan
            self.onPanChanged = onPanChanged
            self.onPanEnded = onPanEnded
            self.onPanCancelled = onPanCancelled
        }

        func attach(to attachment: MagnificationAttachmentView) {
            attachmentView = attachment
            guard let window = attachment.window,
                  hostWindow !== window else { return }
            detach()
            hostWindow = window
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel]) { [weak self] event in
                guard let self else { return event }
                switch event.type {
                case .magnify:
                    handleMagnification(event)
                case .scrollWheel where handlePan(event):
                    return nil
                default:
                    break
                }
                return event
            }
        }

        func detach() {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            eventMonitor = nil
            hostWindow = nil
            accumulatedMagnification = 0
            accumulatedPan = .zero
            isMagnificationActive = false
            isPanActive = false
        }

        private func handleMagnification(_ event: NSEvent) {
            guard let attachmentView,
                  event.window === hostWindow,
                  attachmentView.bounds.contains(attachmentView.convert(event.locationInWindow, from: nil)) else { return }

            if event.phase.contains(.mayBegin) { return }

            if event.phase.contains(.cancelled) {
                if isMagnificationActive { onCancelled() }
                accumulatedMagnification = 0
                isMagnificationActive = false
                return
            }

            if event.phase.contains(.began) || !isMagnificationActive {
                accumulatedMagnification = 0
                isMagnificationActive = true
                onBegan()
            }

            accumulatedMagnification += Double(event.magnification)
            let factor = Self.scaleFactor(for: accumulatedMagnification)
            if event.phase.contains(.ended) {
                onEnded(factor)
                accumulatedMagnification = 0
                isMagnificationActive = false
            } else {
                onChanged(factor)
            }
        }

        private func handlePan(_ event: NSEvent) -> Bool {
            guard let attachmentView,
                  event.window === hostWindow,
                  attachmentView.bounds.contains(attachmentView.convert(event.locationInWindow, from: nil)),
                  event.hasPreciseScrollingDeltas,
                  event.momentumPhase.isEmpty,
                  !event.phase.isEmpty,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }

            if event.phase.contains(.mayBegin) { return true }

            if event.phase.contains(.cancelled) {
                if isPanActive { onPanCancelled() }
                accumulatedPan = .zero
                isPanActive = false
                return true
            }

            if event.phase.contains(.began) || !isPanActive {
                accumulatedPan = .zero
                isPanActive = true
                onPanBegan()
            }

            accumulatedPan.width += event.scrollingDeltaX
            accumulatedPan.height += event.scrollingDeltaY
            if event.phase.contains(.ended) {
                onPanEnded(accumulatedPan)
                accumulatedPan = .zero
                isPanActive = false
            } else {
                onPanChanged(accumulatedPan)
            }
            return true
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
