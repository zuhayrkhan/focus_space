import Foundation

struct FocusCameraIntent: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case canonical
        case free
        case overview
        case framed(UUID)
        case search
    }

    struct Pose: Equatable, Sendable {
        var target: SpatialPoint
        var targetAttention: Double
        var yaw: Double
        var pitch: Double
        var distance: Double

        static let canonical = Self(
            target: SpatialPoint(x: 0, y: 0.05),
            targetAttention: 0.695,
            yaw: 0,
            pitch: 0,
            distance: 9.8
        )

        func bounded() -> Self {
            Self(
                target: SpatialPoint(
                    x: min(max(target.x, -6.5), 6.5),
                    y: min(max(target.y, -4.2), 4.2)
                ),
                targetAttention: min(max(targetAttention, 0), 1),
                yaw: min(max(yaw, -55), 55),
                pitch: min(max(pitch, -34), 34),
                distance: min(max(distance, 4.2), 32)
            )
        }
    }

    var pose: Pose
    var mode: Mode
    var revision: Int
    var isAnimated: Bool

    static let canonical = Self(pose: .canonical, mode: .canonical, revision: 0, isAnimated: false)
}
