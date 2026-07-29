import SwiftUI

enum ColourKeyPresentation: Equatable {
    case hidden
    case button
    case expanded
}

enum WorkspaceChromePolicy {
    static func colourKeyPresentation(
        isEnabled: Bool,
        nodeCount: Int,
        workspaceLevel: WorkspacePresentationLevel,
        isDistractionFree: Bool,
        compactKeyIsExpanded: Bool
    ) -> ColourKeyPresentation {
        guard isEnabled, nodeCount > 0, !isDistractionFree else { return .hidden }
        guard workspaceLevel == .atlas || nodeCount >= 48 else { return .expanded }
        return compactKeyIsExpanded ? .expanded : .button
    }
}

struct WorkspaceViewActions {
    let isDistractionFree: Bool
    let isInspectorVisible: Bool
    let isColourKeyVisible: Bool
    let toggleDistractionFree: () -> Void
    let toggleInspector: () -> Void
    let toggleColourKey: () -> Void
}

private struct WorkspaceViewActionsKey: FocusedValueKey {
    typealias Value = WorkspaceViewActions
}

extension FocusedValues {
    var workspaceViewActions: WorkspaceViewActions? {
        get { self[WorkspaceViewActionsKey.self] }
        set { self[WorkspaceViewActionsKey.self] = newValue }
    }
}
