import Darwin
import Foundation

let focusSpaceProcessStartedAt = Date()

struct ReleasePerformanceSnapshot: Equatable, Sendable {
    let framesPerSecond: Double
    let p95FrameMilliseconds: Double
    let residentMemoryMegabytes: Double
    let launchMilliseconds: Double
}

@MainActor
final class ReleasePerformanceMonitor: ObservableObject {
    @Published private(set) var snapshot: ReleasePerformanceSnapshot?

    private var previousFrame: TimeInterval?
    private var intervals: [Double] = []
    private var workspaceReadyAt: Date?
    private var lastPublishedAt: Date?

    func markWorkspaceReady(at date: Date = .now) {
        if workspaceReadyAt == nil { workspaceReadyAt = date }
    }

    func recordFrame(at date: Date) {
        markWorkspaceReady(at: date)
        let timestamp = date.timeIntervalSinceReferenceDate
        if let previousFrame {
            let interval = timestamp - previousFrame
            if interval > 0, interval < 0.5 { intervals.append(interval) }
        }
        previousFrame = timestamp
        guard intervals.count >= 60,
              lastPublishedAt.map({ date.timeIntervalSince($0) >= 1 }) ?? true else { return }

        let window = Array(intervals.suffix(180))
        let mean = window.reduce(0, +) / Double(window.count)
        let sorted = window.sorted()
        let p95Index = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))
        snapshot = ReleasePerformanceSnapshot(
            framesPerSecond: 1 / mean,
            p95FrameMilliseconds: sorted[p95Index] * 1_000,
            residentMemoryMegabytes: Self.residentMemoryMegabytes(),
            launchMilliseconds: (workspaceReadyAt ?? date).timeIntervalSince(focusSpaceProcessStartedAt) * 1_000
        )
        lastPublishedAt = date
    }

    private static func residentMemoryMegabytes() -> Double {
        var info = proc_taskinfo()
        let byteCount = MemoryLayout<proc_taskinfo>.size
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, pointer, Int32(byteCount))
        }
        guard result == Int32(byteCount) else { return 0 }
        return Double(info.pti_resident_size) / 1_048_576
    }
}
