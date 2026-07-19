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

    static func make(
        from source: SIMD3<Float>,
        sourceSize: SIMD2<Float>,
        to target: SIMD3<Float>,
        targetSize: SIMD2<Float>,
        kind: FocusSceneSnapshot.Relationship.Kind,
        sampleCount: Int = 24
    ) -> Self {
        let start = clippedPoint(from: source, toward: target, size: sourceSize)
        let end = clippedPoint(from: target, toward: source, size: targetSize)
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
        size: SIMD2<Float>
    ) -> SIMD3<Float> {
        let delta = other - center
        let xScale = abs(delta.x) > 0.0001 ? size.x * 0.52 / abs(delta.x) : .greatestFiniteMagnitude
        let yScale = abs(delta.y) > 0.0001 ? size.y * 0.58 / abs(delta.y) : .greatestFiniteMagnitude
        let scale = min(xScale, yScale, 0.46)
        return center + delta * scale
    }
}
