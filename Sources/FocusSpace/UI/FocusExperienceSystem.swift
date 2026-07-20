import AVFoundation
import SwiftUI

enum FocusMotion {
    static let cameraDuration = 0.56
    static let gravityDuration = 0.72
    static let quickFade = Animation.easeInOut(duration: 0.22)
    static let calmSpring = Animation.spring(response: 0.44, dampingFraction: 0.88)
    static let quickSpring = Animation.spring(response: 0.34, dampingFraction: 0.9)
}

enum FocusSoundCue: Sendable {
    case selection
    case depth

    var frequency: Float {
        switch self {
        case .selection: 520
        case .depth: 330
        }
    }
}

enum FocusSoundEnvelope {
    static func samples(
        for cue: FocusSoundCue,
        sampleRate: Float = 44_100,
        duration: Float = 0.075
    ) -> [Float] {
        let count = max(1, Int(sampleRate * duration))
        return (0..<count).map { index in
            let time = Float(index) / sampleRate
            let attack = min(1, time / 0.008)
            let decay = exp(-time * 48)
            return sin(2 * .pi * cue.frequency * time) * attack * decay * 0.028
        }
    }
}

@MainActor
final class FocusSoundPlayer: ObservableObject {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var isPrepared = false

    func play(_ cue: FocusSoundCue) {
        prepareIfNeeded()
        let samples = FocusSoundEnvelope.samples(for: cue)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ), let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() { channel[index] = sample }
        player.scheduleBuffer(buffer)
        if !player.isPlaying { player.play() }
    }

    private func prepareIfNeeded() {
        guard !isPrepared else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.55
        try? engine.start()
        isPrepared = true
    }
}
