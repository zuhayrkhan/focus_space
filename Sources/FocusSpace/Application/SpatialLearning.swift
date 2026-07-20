import Foundation

enum SpatialGuideStep: Int, CaseIterable, Identifiable, Sendable {
    case depth
    case hierarchy
    case branchMovement
    case gravity

    var id: Self { self }

    var title: String {
        switch self {
        case .depth: "Depth is attention"
        case .hierarchy: "Shape relationships"
        case .branchMovement: "Move ideas together"
        case .gravity: "Let time suggest"
        }
    }

    var explanation: String {
        switch self {
        case .depth: "Near and bright means now. Far and quiet means deliberately parked."
        case .hierarchy: "Arrange parent ideas above their detail; links keep the structure readable."
        case .branchMovement: "Option-drag a parent in depth to carry its branch. Add Command to pull one thought free."
        case .gravity: "Dates can gently pull work closer, but a manual move always wins for seven days."
        }
    }
}

enum WorkspaceInteraction: Int, Sendable {
    case selectedThought
    case changedDepth
    case navigatedUniverse
}

struct SpatialLearningProgress: Equatable, Sendable {
    private(set) var rawValue: Int

    init(rawValue: Int = 0) {
        self.rawValue = rawValue
    }

    mutating func record(_ interaction: WorkspaceInteraction) {
        rawValue |= 1 << interaction.rawValue
    }

    func contains(_ interaction: WorkspaceInteraction) -> Bool {
        rawValue & (1 << interaction.rawValue) != 0
    }

    var nextHint: String? {
        if !contains(.selectedThought) { return "Click a thought to bring its branch into view." }
        if !contains(.changedDepth) { return "Option-drag a thought up or down to change its attention." }
        if !contains(.navigatedUniverse) { return "Drag empty space to look around the universe. Command-0 always brings you home." }
        return nil
    }
}
