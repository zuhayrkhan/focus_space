import SwiftUI

struct PerformanceHUD: View {
    @ObservedObject var monitor: ReleasePerformanceMonitor
    @ObservedObject var store: FocusSpaceStore

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            Group {
                if let snapshot = monitor.snapshot {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("RELEASE PROFILE")
                            .font(.caption2.weight(.bold))
                        Text("\(snapshot.framesPerSecond.formatted(.number.precision(.fractionLength(1)))) fps · p95 \(snapshot.p95FrameMilliseconds.formatted(.number.precision(.fractionLength(1)))) ms")
                        Text("\(snapshot.residentMemoryMegabytes.formatted(.number.precision(.fractionLength(0)))) MB · launch \(snapshot.launchMilliseconds.formatted(.number.precision(.fractionLength(0)))) ms")
                        if let autosave = store.lastAutosaveLatencyMilliseconds {
                            Text("autosave \(autosave.formatted(.number.precision(.fractionLength(0)))) ms")
                        }
                    }
                } else {
                    Text("RELEASE PROFILE · sampling…")
                }
            }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(9)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 9))
                .onChange(of: context.date, initial: true) { _, date in
                    monitor.recordFrame(at: date)
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
