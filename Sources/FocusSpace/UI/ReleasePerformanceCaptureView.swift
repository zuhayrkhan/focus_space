import SwiftUI

struct ReleasePerformanceCaptureView: View {
    @ObservedObject var monitor: ReleasePerformanceMonitor
    @ObservedObject var store: FocusSpaceStore
    let configuration: ReleasePerformanceConfiguration

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            Color.clear
                .frame(width: 1, height: 1)
                .onChange(of: context.date, initial: true) { _, date in
                    monitor.recordFrame(at: date)
                }
        }
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
