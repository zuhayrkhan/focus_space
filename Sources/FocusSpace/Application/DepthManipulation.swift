import Foundation

struct DepthManipulation: Equatable, Sendable {
    struct Landing: Equatable, Sendable {
        let attention: Double
        let band: AttentionBand?
    }

    static let semanticDepthSpan = 4.1
    static let magneticRadius = 0.045

    static func attention(
        origin: Double,
        verticalTranslation: Double,
        viewportHeight: Double,
        cameraDistance: Double,
        fieldOfViewDegrees: Double = 39
    ) -> Double {
        guard viewportHeight > 0 else { return clamped(origin) }
        let halfFieldOfView = fieldOfViewDegrees * .pi / 360
        let interactionPlaneHeight = 2 * max(cameraDistance, 0.1) * tan(halfFieldOfView)
        let planeDisplacement = -verticalTranslation / viewportHeight * interactionPlaneHeight
        return clamped(origin + planeDisplacement / semanticDepthSpan)
    }

    static func landing(for attention: Double) -> Landing {
        let attention = clamped(attention)
        let nearest = AttentionBand.nearest(to: attention)
        guard abs(nearest.attention - attention) <= magneticRadius else {
            return Landing(attention: attention, band: nil)
        }
        return Landing(attention: nearest.attention, band: nearest)
    }

    private static func clamped(_ attention: Double) -> Double {
        min(max(attention, 0), 1)
    }
}
