import Foundation

enum DemoScene: String, CaseIterable, Identifiable, Sendable {
    private struct Specification {
        let title: String
        let x: Double
        let y: Double
        let attention: Double
        let parentIndex: Int?
        let kind: FocusNodeKind
        let urgency: FocusNodeUrgency
        let isEnabled: Bool

        init(
            _ title: String,
            _ x: Double,
            _ y: Double,
            _ attention: Double,
            _ parentIndex: Int? = nil,
            kind: FocusNodeKind = .task,
            urgency: FocusNodeUrgency = .none,
            isEnabled: Bool = true
        ) {
            self.title = title
            self.x = x
            self.y = y
            self.attention = attention
            self.parentIndex = parentIndex
            self.kind = kind
            self.urgency = urgency
            self.isEnabled = isEnabled
        }
    }

    case northStar = "North-star composition"
    case shallowHierarchy = "Shallow hierarchy"
    case deepHierarchy = "Deep hierarchy"
    case denseMap = "Dense map"
    case parkedWork = "Parked work"
    case emptySpace = "Empty space"

    var id: Self { self }

    var slug: String {
        switch self {
        case .northStar: return "north-star"
        case .shallowHierarchy: return "shallow"
        case .deepHierarchy: return "deep"
        case .denseMap: return "dense"
        case .parkedWork: return "parked"
        case .emptySpace: return "empty"
        }
    }

    init?(slug: String) {
        guard let match = Self.allCases.first(where: { $0.slug == slug }) else { return nil }
        self = match
    }

    var map: FocusMap {
        switch self {
        case .northStar:
            return Self.makeMap(
                title: rawValue,
                specifications: [
                    Specification("System Platform", 0, 1.4, 0.48, kind: .project),
                    Specification("Critical Now", 0, -0.15, 0.98, kind: .project, urgency: .overdue),
                    Specification("Risk & Compliance", -2.25, 0.55, 0.72, 0, kind: .group),
                    Specification("UI / UX", -0.8, 0.62, 0.68, 0, kind: .group),
                    Specification("Performance", 0.8, 0.62, 0.64, 0, kind: .group),
                    Specification("Integrations", 2.25, 0.55, 0.60, 0, kind: .group),
                    Specification("Reg change impact", -2.8, -0.55, 0.54, 2, urgency: .overdue),
                    Specification("Audit preparation and evidence review", -1.75, -0.55, 0.50, 2, urgency: .soon),
                    Specification("Update model", -1.35, -1.55, 0.91, 1),
                    Specification("競合分析 / Competitor analysis", 0, -1.65, 0.86, 1),
                    Specification("Deck for Exec mtg", 1.35, -1.55, 0.82, 1, kind: .reference),
                    Specification("Investigate spikes", 1.8, -0.55, 0.48, 5),
                    Specification("Data quality check", 2.8, -0.55, 0.44, 5, isEnabled: false),
                    Specification("Ideas / Future / Maybe", -2.6, 2.35, 0.14, kind: .someday),
                    Specification("People & Processes", 2.6, 2.3, 0.18, kind: .project),
                    Specification("Ideas structure", 0, 2.45, 0.23, kind: .reference)
                ]
            )
        case .shallowHierarchy:
            return Self.makeMap(
                title: rawValue,
                specifications: [
                    Specification("Morning focus", 0, 0.8, 0.88, kind: .project),
                    Specification("Write the proposal", -1.55, -0.45, 0.78, 0),
                    Specification("Review the prototype", 0, -0.65, 0.70, 0, kind: .reference),
                    Specification("Call the first explorer", 1.55, -0.45, 0.62, 0, urgency: .soon)
                ]
            )
        case .deepHierarchy:
            return Self.makeMap(
                title: rawValue,
                specifications: [
                    Specification("Release Focus Space", 0, 2.0, 0.64, kind: .project),
                    Specification("Experience", -2.6, 1.0, 0.70, 0, kind: .group),
                    Specification("Intelligence", 0, 1.0, 0.66, 0, kind: .group),
                    Specification("Foundations", 2.6, 1.0, 0.62, 0, kind: .group),
                    Specification("Depth language", -3.4, 0, 0.76, 1, kind: .group),
                    Specification("Motion", -2.05, 0, 0.72, 1, kind: .group),
                    Specification("Suggestions", -0.7, 0, 0.68, 2, kind: .group),
                    Specification("Search", 0.7, 0, 0.64, 2, kind: .group),
                    Specification("Persistence", 2.05, 0, 0.60, 3, kind: .group),
                    Specification("Accessibility", 3.4, 0, 0.56, 3, kind: .group),
                    Specification("Tune focus glow", -3.3, -0.95, 0.92, 4, urgency: .soon),
                    Specification("Contrast checks", -2.2, -1.6, 0.84, 4),
                    Specification("Spring response", -1.4, -0.95, 0.80, 5),
                    Specification("Gravity cues", -0.55, -1.6, 0.76, 6),
                    Specification("Semantic zoom", 0.35, -0.95, 0.72, 7),
                    Specification("JSON migration", 1.25, -1.6, 0.68, 8, kind: .reference),
                    Specification("Keyboard flow", 2.1, -0.95, 0.64, 9),
                    Specification("Reduce Motion", 3.1, -1.6, 0.60, 9),
                    Specification("Focus selected branch", 0.35, -2.4, 0.82, 14)
                ]
            )
        case .denseMap:
            let specs = (0..<32).map { index in
                let column = Double(index % 7) - 3
                let row = Double(index / 7) - 2
                let kinds = FocusNodeKind.allCases
                return Specification(
                    index == 17 ? "مراجعة تجربة المستخدم" : "Thought \(index + 1)",
                    column * 1.15,
                    -row * 0.85,
                    0.2 + Double((index * 17) % 70) / 100,
                    index < 7 ? nil : (index % 7),
                    kind: kinds[index % kinds.count],
                    urgency: index % 13 == 0 ? .overdue : (index % 9 == 0 ? .soon : .none),
                    isEnabled: index % 11 != 0
                )
            }
            return Self.makeMap(title: rawValue, specifications: specs)
        case .parkedWork:
            return Self.makeMap(
                title: rawValue,
                specifications: [
                    Specification("In focus", 0, 0, 0.92, kind: .project),
                    Specification("مراجعة تجربة المستخدم", -1.5, -0.8, 0.55, 0, kind: .group),
                    Specification("Later", 1.5, -0.8, 0.27, 0, isEnabled: false),
                    Specification("Someday", 2.8, 1.6, 0.04, kind: .someday)
                ]
            )
        case .emptySpace:
            return FocusMap(title: rawValue)
        }
    }

    private static func makeMap(
        title: String,
        specifications: [Specification]
    ) -> FocusMap {
        let namespace = "focus-space-demo-\(title)"
        let ids = specifications.indices.map { deterministicUUID(namespace: namespace, index: $0) }
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let nodes = specifications.enumerated().map { index, specification in
            FocusNode(
                id: ids[index],
                title: specification.title,
                kind: specification.kind,
                position: SpatialPoint(x: specification.x, y: specification.y),
                attention: specification.attention,
                parentID: specification.parentIndex.map { ids[$0] },
                urgency: specification.urgency,
                isEnabled: specification.isEnabled,
                createdAt: timestamp,
                updatedAt: timestamp
            )
        }
        return FocusMap(title: title, nodes: nodes)
    }

    private static func deterministicUUID(namespace: String, index: Int) -> UUID {
        let bytes = Array("\(namespace)-\(index)".utf8)
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let suffix = String(format: "%012llx", hash & 0x0000_FFFF_FFFF_FFFF)
        return UUID(uuidString: "F0C05ACE-0001-4000-8000-\(suffix)")!
    }
}
