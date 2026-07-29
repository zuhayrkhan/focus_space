import Foundation
import OSLog

enum FocusPerformanceOperation: String, CaseIterable, Codable, Sendable {
    case launchToInteractive = "launch_to_interactive"
    case snapshotDerivation = "snapshot_derivation"
    case rendererReconciliation = "renderer_reconciliation"
    case relationshipReconciliation = "relationship_reconciliation"
    case accessibilityRepresentation = "accessibility_representation"
    case arrange = "arrange"
    case searchFraming = "search_framing"
    case optionDragPreview = "option_drag_preview"

    var signpostName: StaticString {
        switch self {
        case .launchToInteractive: "Launch To Interactive"
        case .snapshotDerivation: "Snapshot Derivation"
        case .rendererReconciliation: "Renderer Reconciliation"
        case .relationshipReconciliation: "Relationship Reconciliation"
        case .accessibilityRepresentation: "Accessibility Representation"
        case .arrange: "Arrange"
        case .searchFraming: "Search Framing"
        case .optionDragPreview: "Option Drag Preview"
        }
    }
}

struct FocusPerformanceMetricSummary: Codable, Equatable, Sendable {
    let sampleCount: Int
    let meanMilliseconds: Double
    let p50Milliseconds: Double
    let p95Milliseconds: Double
    let maximumMilliseconds: Double
}

final class FocusPerformanceRecorder: @unchecked Sendable {
    static let shared = FocusPerformanceRecorder()

    private let lock = NSLock()
    private var samples: [FocusPerformanceOperation: [Double]] = [:]
    private var launchRecorded = false

    func record(_ operation: FocusPerformanceOperation, milliseconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        if operation == .launchToInteractive {
            guard !launchRecorded else { return }
            launchRecorded = true
        }
        samples[operation, default: []].append(milliseconds)
    }

    func summaries() -> [String: FocusPerformanceMetricSummary] {
        lock.lock()
        let snapshot = samples
        lock.unlock()
        return Dictionary(uniqueKeysWithValues: snapshot.map { operation, values in
            let sorted = values.sorted()
            let mean = sorted.reduce(0, +) / Double(max(sorted.count, 1))
            return (
                operation.rawValue,
                FocusPerformanceMetricSummary(
                    sampleCount: sorted.count,
                    meanMilliseconds: mean,
                    p50Milliseconds: percentile(0.50, in: sorted),
                    p95Milliseconds: percentile(0.95, in: sorted),
                    maximumMilliseconds: sorted.last ?? 0
                )
            )
        })
    }

    func reset() {
        lock.lock()
        samples.removeAll()
        launchRecorded = false
        lock.unlock()
    }

    private func percentile(_ percentile: Double, in sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * percentile).rounded(.up)))
        return sorted[index]
    }
}

enum FocusPerformance {
    private static let signposter = OSSignposter(
        subsystem: "com.zuhayrkhan.FocusSpace",
        category: "MeasuredExperience"
    )
    private static let launchContext: (startedAt: UInt64, interval: OSSignpostIntervalState) = {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let interval = signposter.beginInterval(
            FocusPerformanceOperation.launchToInteractive.signpostName
        )
        return (startedAt, interval)
    }()
    private static var launchInterval: OSSignpostIntervalState? = launchContext.interval

    static func beginLaunch() {
        _ = launchContext
    }

    @discardableResult
    static func measure<T>(
        _ operation: FocusPerformanceOperation,
        _ body: () throws -> T
    ) rethrows -> T {
        let interval = signposter.beginInterval(operation.signpostName)
        let startedAt = DispatchTime.now().uptimeNanoseconds
        defer {
            let endedAt = DispatchTime.now().uptimeNanoseconds
            signposter.endInterval(operation.signpostName, interval)
            FocusPerformanceRecorder.shared.record(
                operation,
                milliseconds: Double(endedAt - startedAt) / 1_000_000
            )
        }
        return try body()
    }

    static func markLaunchInteractive() {
        guard let interval = launchInterval else { return }
        launchInterval = nil
        let endedAt = DispatchTime.now().uptimeNanoseconds
        signposter.endInterval(FocusPerformanceOperation.launchToInteractive.signpostName, interval)
        FocusPerformanceRecorder.shared.record(
            .launchToInteractive,
            milliseconds: Double(endedAt - launchContext.startedAt) / 1_000_000
        )
    }
}
