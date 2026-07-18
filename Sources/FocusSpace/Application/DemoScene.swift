import Foundation

enum DemoScene: String, CaseIterable, Identifiable, Sendable {
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
                    ("System Platform", 0, 1.4, 0.48, nil),
                    ("Critical Now", 0, -0.15, 0.98, nil),
                    ("Risk & Compliance", -2.25, 0.55, 0.72, 0),
                    ("UI / UX", -0.8, 0.62, 0.68, 0),
                    ("Performance", 0.8, 0.62, 0.64, 0),
                    ("Integrations", 2.25, 0.55, 0.60, 0),
                    ("Reg change impact", -2.8, -0.55, 0.54, 2),
                    ("Audit prep", -1.75, -0.55, 0.50, 2),
                    ("Update model", -1.35, -1.55, 0.91, 1),
                    ("Competitor analysis", 0, -1.65, 0.86, 1),
                    ("Deck for Exec mtg", 1.35, -1.55, 0.82, 1),
                    ("Investigate spikes", 1.8, -0.55, 0.48, 5),
                    ("Data quality check", 2.8, -0.55, 0.44, 5),
                    ("Ideas / Future / Maybe", -2.6, 2.35, 0.14, nil),
                    ("People & Processes", 2.6, 2.3, 0.18, nil),
                    ("Ideas structure", 0, 2.45, 0.23, nil)
                ]
            )
        case .shallowHierarchy:
            return Self.makeMap(
                title: rawValue,
                specifications: [
                    ("Morning focus", 0, 0.8, 0.88, nil),
                    ("Write the proposal", -1.55, -0.45, 0.78, 0),
                    ("Review the prototype", 0, -0.65, 0.70, 0),
                    ("Call the first explorer", 1.55, -0.45, 0.62, 0)
                ]
            )
        case .deepHierarchy:
            return Self.makeMap(
                title: rawValue,
                specifications: [
                    ("Release Focus Space", 0, 2.1, 0.72, nil),
                    ("Experience", 0, 1.05, 0.76, 0),
                    ("Depth language", 0, 0, 0.80, 1),
                    ("Lighting", 0, -1.05, 0.84, 2),
                    ("Tune focus glow", 0, -2.1, 0.92, 3)
                ]
            )
        case .denseMap:
            let specs = (0..<32).map { index in
                let column = Double(index % 7) - 3
                let row = Double(index / 7) - 2
                return ("Thought \(index + 1)", column * 1.15, -row * 0.85, 0.2 + Double((index * 17) % 70) / 100, index < 7 ? nil : (index % 7))
            }
            return Self.makeMap(title: rawValue, specifications: specs)
        case .parkedWork:
            return Self.makeMap(
                title: rawValue,
                specifications: [
                    ("In focus", 0, 0, 0.92, nil),
                    ("Next", -1.5, -0.8, 0.55, 0),
                    ("Later", 1.5, -0.8, 0.27, 0),
                    ("Someday", 2.8, 1.6, 0.04, nil)
                ]
            )
        case .emptySpace:
            return FocusMap(title: rawValue)
        }
    }

    private static func makeMap(
        title: String,
        specifications: [(String, Double, Double, Double, Int?)]
    ) -> FocusMap {
        let namespace = "focus-space-demo-\(title)"
        let ids = specifications.indices.map { deterministicUUID(namespace: namespace, index: $0) }
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let nodes = specifications.enumerated().map { index, specification in
            FocusNode(
                id: ids[index],
                title: specification.0,
                position: SpatialPoint(x: specification.1, y: specification.2),
                attention: specification.3,
                parentID: specification.4.map { ids[$0] },
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
