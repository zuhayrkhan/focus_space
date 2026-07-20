import Foundation
import simd

struct RelationshipCurveGeometry: Equatable, Sendable {
    struct Segment: Equatable, Sendable {
        let start: SIMD3<Float>
        let end: SIMD3<Float>
    }

    let points: [SIMD3<Float>]

    var solidSegments: [Segment] {
        zip(points, points.dropFirst()).map(Segment.init)
    }

    var dashedSegments: [Segment] {
        solidSegments.enumerated().compactMap { index, segment in
            index.isMultiple(of: 2) ? segment : nil
        }
    }

    func pointRuns(for kind: FocusSceneSnapshot.Relationship.Kind) -> [[SIMD3<Float>]] {
        guard kind == .crossLink else { return [points] }
        let dashSegments = 4
        let gapSegments = 3
        return stride(from: 0, to: points.count - 1, by: dashSegments + gapSegments).compactMap { start in
            let end = min(start + dashSegments, points.count - 1)
            guard end > start else { return nil }
            return Array(points[start...end])
        }
    }

    static func make(
        from source: SIMD3<Float>,
        sourceSize: SIMD2<Float>,
        to target: SIMD3<Float>,
        targetSize: SIMD2<Float>,
        kind: FocusSceneSnapshot.Relationship.Kind,
        sourceShape: NodeSilhouette = .panel,
        targetShape: NodeSilhouette = .panel,
        sampleCount: Int = 24
    ) -> Self {
        let start = clippedPoint(from: source, toward: target, size: sourceSize, shape: sourceShape)
        let end = clippedPoint(from: target, toward: source, size: targetSize, shape: targetShape)
        let delta = end - start
        let planarLength = simd_length(SIMD2<Float>(delta.x, delta.y))
        let bend = max(0.16, min(planarLength * 0.18, 0.62))
        let perpendicular = planarLength > 0.001
            ? SIMD3<Float>(-delta.y / planarLength, delta.x / planarLength, 0)
            : SIMD3<Float>(0, 1, 0)
        let lateral = kind == .crossLink ? perpendicular * bend : .zero
        let depthLift: Float = kind == .crossLink ? 0.24 : 0.12
        let controlA = start + delta * 0.32 + lateral + SIMD3<Float>(0, 0, depthLift)
        let controlB = start + delta * 0.68 + lateral + SIMD3<Float>(0, 0, depthLift)
        let count = max(sampleCount, 4)
        let points = (0...count).map { index -> SIMD3<Float> in
            let t = Float(index) / Float(count)
            let inverse = 1 - t
            return inverse * inverse * inverse * start
                + 3 * inverse * inverse * t * controlA
                + 3 * inverse * t * t * controlB
                + t * t * t * end
        }
        return Self(points: points)
    }

    private static func clippedPoint(
        from center: SIMD3<Float>,
        toward other: SIMD3<Float>,
        size: SIMD2<Float>,
        shape: NodeSilhouette
    ) -> SIMD3<Float> {
        let delta = other - center
        let halfWidth = size.x * 0.5
        let halfHeight = size.y * 0.5
        let x = abs(delta.x)
        let y = abs(delta.y)
        guard x > 0.0001 || y > 0.0001 else { return center }
        let scale: Float = switch shape {
        case .ellipse, .circle:
            1 / sqrt((x * x) / (halfWidth * halfWidth) + (y * y) / (halfHeight * halfHeight))
        case .diamond:
            1 / (x / halfWidth + y / halfHeight)
        case .panel, .capsule, .compact, .note, .ghost:
            min(
                x > 0.0001 ? halfWidth / x : .greatestFiniteMagnitude,
                y > 0.0001 ? halfHeight / y : .greatestFiniteMagnitude
            )
        }
        // Tuck the cap just beneath the card face so perspective never reveals a gap.
        return center + delta * (scale * 0.96)
    }
}
