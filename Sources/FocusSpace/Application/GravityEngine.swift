import Foundation

struct GravityAssessment: Equatable, Sendable {
    let attention: Double
    let urgency: FocusNodeUrgency
    let reason: String
    let isInfluencing: Bool
}

enum GravityEngine {
    static let manualOverrideDuration: TimeInterval = 7 * 24 * 60 * 60

    static func assess(_ node: FocusNode, at now: Date) -> GravityAssessment {
        if let override = node.lastManualOverride {
            let release = override.addingTimeInterval(manualOverrideDuration)
            if release > now {
                return GravityAssessment(
                    attention: node.attention,
                    urgency: node.urgency,
                    reason: "Manual attention holds until \(release.formatted(date: .abbreviated, time: .shortened)).",
                    isInfluencing: false
                )
            }
        }

        let candidates = [
            node.dueDate.map { dueAssessment(date: $0, now: now) },
            node.milestoneDate.map { milestoneAssessment(date: $0, now: now) },
            node.reminderDate.map { reminderAssessment(date: $0, now: now) }
        ].compactMap { $0 }

        guard let strongest = candidates.max(by: { $0.attention < $1.attention }),
              strongest.attention > node.attention + 0.005 else {
            return GravityAssessment(
                attention: node.attention,
                urgency: node.urgency,
                reason: candidates.isEmpty ? "No time signals are pulling this thought." : "Its current attention is already stronger than its time pull.",
                isInfluencing: false
            )
        }

        return GravityAssessment(
            attention: strongest.attention,
            urgency: strongest.urgency,
            reason: strongest.reason,
            isInfluencing: true
        )
    }

    private static func dueAssessment(date: Date, now: Date) -> GravityAssessment {
        let days = date.timeIntervalSince(now) / 86_400
        if days < 0 {
            return .init(attention: 0.97, urgency: .overdue, reason: "The due date has passed, so gravity is pulling this forward.", isInfluencing: true)
        }
        if days <= 7 {
            let attention = 0.84 + (7 - days) / 7 * 0.11
            return .init(attention: attention, urgency: .soon, reason: "Due within \(dayPhrase(days)); gravity strengthens as the date approaches.", isInfluencing: true)
        }
        if days <= 30 {
            let attention = 0.62 + (30 - days) / 23 * 0.18
            return .init(attention: attention, urgency: .soon, reason: "Due within \(dayPhrase(days)); gravity is beginning to draw it closer.", isInfluencing: true)
        }
        return .init(attention: 0, urgency: .none, reason: "The due date is still distant.", isInfluencing: false)
    }

    private static func milestoneAssessment(date: Date, now: Date) -> GravityAssessment {
        let days = date.timeIntervalSince(now) / 86_400
        if days < 0 {
            return .init(attention: 0.86, urgency: .soon, reason: "Its milestone has passed, so gravity is keeping it near.", isInfluencing: true)
        }
        if days <= 14 {
            let attention = 0.68 + (14 - days) / 14 * 0.16
            return .init(attention: attention, urgency: .soon, reason: "A milestone is within \(dayPhrase(days)).", isInfluencing: true)
        }
        return .init(attention: 0, urgency: .none, reason: "The milestone is still distant.", isInfluencing: false)
    }

    private static func reminderAssessment(date: Date, now: Date) -> GravityAssessment {
        guard date <= now else {
            return .init(attention: 0, urgency: .none, reason: "The reminder has not fired yet.", isInfluencing: false)
        }
        return .init(attention: 0.76, urgency: .soon, reason: "Its reminder has fired, so gravity is bringing it into view.", isInfluencing: true)
    }

    private static func dayPhrase(_ days: Double) -> String {
        let rounded = max(1, Int(ceil(days)))
        return rounded == 1 ? "1 day" : "\(rounded) days"
    }
}
