import Foundation

enum SceneQualityProfile: String, CaseIterable, Sendable {
    case efficient
    case balanced
    case cinematic

    var starCount: Int {
        switch self {
        case .efficient: 84
        case .balanced: 168
        case .cinematic: 280
        }
    }

    var guideSegmentCount: Int {
        switch self {
        case .efficient: 40
        case .balanced: 64
        case .cinematic: 96
        }
    }

    static func recommended(isLowPowerModeEnabled: Bool, physicalMemory: UInt64) -> Self {
        if isLowPowerModeEnabled || physicalMemory < 8_000_000_000 { return .efficient }
        if physicalMemory >= 24_000_000_000 { return .cinematic }
        return .balanced
    }

    static var recommended: Self {
        if let index = CommandLine.arguments.firstIndex(of: "--quality"),
           CommandLine.arguments.indices.contains(index + 1),
           let override = Self(rawValue: CommandLine.arguments[index + 1]) {
            return override
        }
        return recommended(
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            physicalMemory: ProcessInfo.processInfo.physicalMemory
        )
    }
}
