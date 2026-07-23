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
        case .hierarchy: "Solid blue lines form the parent–child map. Dashed purple lines relate ideas without changing their hierarchy; add them from Related thoughts in the inspector."
        case .branchMovement: "Two-finger drag vertically over a parent to carry its branch in depth. Option-drag a thought to move its connected map."
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
        if !contains(.changedDepth) { return "Two-finger drag vertically over a thought to move its branch through attention." }
        if !contains(.navigatedUniverse) { return "Drag empty space to look around the universe. Command-0 always brings you home." }
        return nil
    }
}
