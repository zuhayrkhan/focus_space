import Metal

enum WorkspaceRendererAvailability {
    static var supportsAdvancedEffects: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    static func usesListFallback(
        preference: Bool,
        arguments: [String] = CommandLine.arguments,
        supportsAdvancedEffects: Bool = supportsAdvancedEffects
    ) -> Bool {
        preference || arguments.contains("--accessible-list") || !supportsAdvancedEffects
    }
}
