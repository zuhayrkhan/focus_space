import AppKit
import SwiftUI

struct VisualColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    func interpolated(to other: VisualColor, fraction: Double) -> VisualColor {
        let fraction = min(max(fraction, 0), 1)
        return VisualColor(
            red + (other.red - red) * fraction,
            green + (other.green - green) * fraction,
            blue + (other.blue - blue) * fraction,
            alpha + (other.alpha - alpha) * fraction
        )
    }
}

struct FocusVisualTokens: Equatable, Sendable {
    let canvasDeep = VisualColor(0.012, 0.025, 0.052)
    let canvasMid = VisualColor(0.025, 0.085, 0.15)
    let focusCore = VisualColor(0.78, 0.91, 1)
    let focusBlue = VisualColor(0.20, 0.52, 1)
    let guideBlue = VisualColor(0.23, 0.55, 0.92, 0.18)
    let starlight = VisualColor(0.55, 0.78, 1, 0.52)
    let warmDust = VisualColor(1, 0.47, 0.24, 0.48)
    let glassStroke = VisualColor(0.62, 0.82, 1, 0.16)

    let cameraFieldOfView: Float = 39
    let cameraDistance: Float = 9.8
    let attentionNearZ: Float = 1.25
    let attentionFarZ: Float = -2.85
    let ambientRevolutionSeconds = 360.0

    static let midnight = FocusVisualTokens()
}
