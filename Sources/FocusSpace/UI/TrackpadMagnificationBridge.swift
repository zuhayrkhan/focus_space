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
    final class Coordinator: NSObject, NSGestureRecognizerDelegate {
        var onBegan: () -> Void
        var onChanged: (Double) -> Void
        var onEnded: (Double) -> Void
        var onCancelled: () -> Void
        weak var attachmentView: MagnificationAttachmentView?
        private weak var hostView: NSView?

        private lazy var recognizer: NSMagnificationGestureRecognizer = {
            let recognizer = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnification(_:)))
            recognizer.delegate = self
            return recognizer
        }()

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
            guard let contentView = attachment.window?.contentView,
                  hostView !== contentView else { return }
            detach()
            hostView = contentView
            contentView.addGestureRecognizer(recognizer)
        }

        func detach() {
            if let hostView { hostView.removeGestureRecognizer(recognizer) }
            hostView = nil
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
            guard let attachmentView,
                  attachmentView.window != nil else { return false }
            let point = gestureRecognizer.location(in: attachmentView)
            return attachmentView.bounds.contains(point)
        }

        func gestureRecognizer(
            _ gestureRecognizer: NSGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func handleMagnification(_ recognizer: NSMagnificationGestureRecognizer) {
            let factor = Self.scaleFactor(for: Double(recognizer.magnification))
            switch recognizer.state {
            case .began:
                onBegan()
                onChanged(factor)
            case .changed:
                onChanged(factor)
            case .ended:
                onEnded(factor)
            case .cancelled, .failed:
                onCancelled()
            case .possible:
                break
            @unknown default:
                onCancelled()
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
