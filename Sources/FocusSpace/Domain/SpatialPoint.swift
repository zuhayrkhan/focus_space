import Foundation

struct SpatialPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    static let zero = SpatialPoint(x: 0, y: 0)
}
