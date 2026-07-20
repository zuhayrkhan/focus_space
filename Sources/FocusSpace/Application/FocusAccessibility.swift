import Foundation

struct FocusAccessibilityDescriptor: Equatable, Sendable {
    let label: String
    let value: String
    let hint: String

    static func node(
        _ item: FocusSceneSnapshot.Item,
        in map: FocusMap
    ) -> Self {
        var details = [item.kind.displayName]
        details.append("\(Int((item.attention * 100).rounded())) percent attention")

        if let parentID = item.parentID, let parent = map.node(id: parentID) {
            details.append("child of \(parent.title)")
        } else {
            details.append("top-level thought")
        }

        let childCount = map.nodes.count { $0.parentID == item.id }
        if childCount > 0 {
            details.append(childCount == 1 ? "1 child" : "\(childCount) children")
        }

        let relatedTitles = map.nodes
            .filter { item.id == $0.id ? false : ($0.relatedNodeIDs.contains(item.id) || map.node(id: item.id)?.relatedNodeIDs.contains($0.id) == true) }
            .map(\.title)
        if !relatedTitles.isEmpty {
            details.append("related to \(relatedTitles.joined(separator: ", "))")
        }

        switch item.urgency {
        case .none: break
        case .soon: details.append("due soon")
        case .overdue: details.append("overdue")
        }
        if item.isDimmed { details.append("outside the current view") }
        if item.isGravityInfluenced, let reason = item.gravityReason { details.append(reason) }

        let notes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = notes.isEmpty
            ? "Press to select. Use accessibility actions to change depth or hierarchy."
            : "\(notes) Press to select. Use accessibility actions to change depth or hierarchy."
        return Self(label: item.title, value: details.joined(separator: ", "), hint: hint)
    }

    static func relationship(
        _ relationship: FocusSceneSnapshot.Relationship,
        in map: FocusMap
    ) -> Self? {
        guard let source = map.node(id: relationship.sourceID),
              let target = map.node(id: relationship.targetID) else { return nil }
        let kind = relationship.kind == .hierarchy ? "Hierarchy link" : "Related-thought link"
        return Self(
            label: "\(kind) from \(source.title) to \(target.title)",
            value: "\(Int((relationship.attention * 100).rounded())) percent attention",
            hint: "Select either connected thought to inspect or move the relationship."
        )
    }
}
