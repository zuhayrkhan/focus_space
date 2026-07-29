import AppKit
import Foundation

struct ReleasePerformanceConfiguration: Equatable, Sendable {
    let outputURL: URL
    let fixture: String
    let windowSize: String
    let captureSeconds: Double

    static func current(arguments: [String] = CommandLine.arguments) -> Self? {
        guard let reportIndex = arguments.firstIndex(of: "--performance-report"),
              arguments.indices.contains(reportIndex + 1) else { return nil }
        let outputURL = URL(fileURLWithPath: arguments[reportIndex + 1])
        let fixture = argument(after: "--demo", in: arguments) ?? "personal"
        let windowSize = argument(after: "--window-size", in: arguments) ?? "standard"
        let seconds = argument(after: "--performance-seconds", in: arguments)
            .flatMap(Double.init)
            .map { min(max($0, 3), 30) }
            ?? 5
        return Self(
            outputURL: outputURL,
            fixture: fixture,
            windowSize: windowSize,
            captureSeconds: seconds
        )
    }

    private static func argument(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

struct ReleasePerformanceReport: Codable, Equatable, Sendable {
    let capturedAt: Date
    let fixture: String
    let windowSize: String
    let windowWidth: Double
    let windowHeight: Double
    let nodeCount: Int
    let workspacePresentationLevel: String
    let framesPerSecond: Double
    let p95FrameMilliseconds: Double
    let residentMemoryMegabytes: Double
    let launchMilliseconds: Double
    let diagnosticPreviewFramesPerSecond: Double
    let spatialAccessibilityItemCount: Int
    let omittedSpatialAccessibilityItemCount: Int
    let completeListItemCount: Int
    let operations: [String: FocusPerformanceMetricSummary]

    @MainActor
    static func make(
        configuration: ReleasePerformanceConfiguration,
        store: FocusSpaceStore,
        monitor: ReleasePerformanceMonitor
    ) -> Self {
        let scene = store.sceneSnapshot
        let accessibility = FocusPerformance.measure(.accessibilityRepresentation) {
            AccessibilitySceneProjection.make(
                snapshot: scene,
                map: store.map,
                selection: store.selection
            )
        }
        let operationMetrics = FocusPerformanceRecorder.shared.summaries()
        let monitorSnapshot = monitor.snapshot
        let contentBounds = (
            NSApplication.shared.keyWindow
                ?? NSApplication.shared.windows.first
        )?.contentView?.bounds ?? .zero
        let launch = operationMetrics[FocusPerformanceOperation.launchToInteractive.rawValue]?
            .maximumMilliseconds
            ?? monitorSnapshot?.launchMilliseconds
            ?? 0
        return Self(
            capturedAt: .now,
            fixture: configuration.fixture,
            windowSize: configuration.windowSize,
            windowWidth: contentBounds.width,
            windowHeight: contentBounds.height,
            nodeCount: store.map.nodes.count,
            workspacePresentationLevel: store.workspacePresentationLevel.rawValue,
            framesPerSecond: monitorSnapshot?.framesPerSecond ?? 0,
            p95FrameMilliseconds: monitorSnapshot?.p95FrameMilliseconds ?? 0,
            residentMemoryMegabytes: monitorSnapshot?.residentMemoryMegabytes ?? 0,
            launchMilliseconds: launch,
            diagnosticPreviewFramesPerSecond: monitor.diagnosticPreviewFramesPerSecond ?? 0,
            spatialAccessibilityItemCount: accessibility.items.count,
            omittedSpatialAccessibilityItemCount: accessibility.omittedItemCount,
            completeListItemCount: scene.items.count,
            operations: operationMetrics
        )
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
