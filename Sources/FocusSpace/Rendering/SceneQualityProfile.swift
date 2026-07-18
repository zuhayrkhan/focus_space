import Foundation

enum SceneQualityProfile: String, CaseIterable, Sendable {
    case efficient
    case balanced
    case cinematic

    var starCount: Int {
        switch self {
        case .efficient: 48
        case .balanced: 96
        case .cinematic: 160
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
        recommended(
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            physicalMemory: ProcessInfo.processInfo.physicalMemory
        )
    }
}
