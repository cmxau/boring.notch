//
//  AgentSoundPlayer.swift
//  boringNotch
//
//  Short 8-bit chimes for agent events, synthesised as square waves.
//

import AVFoundation
import Defaults

/// Agent events that can play a sound.
enum AgentSoundCue: String, CaseIterable, Identifiable {
    /// A new agent session appeared.
    case sessionStarted
    /// An agent needs a permission or plan decision.
    case attention
    /// An agent asked a question.
    case question
    /// An agent finished its turn.
    case done
    /// An agent's turn failed.
    case error

    var id: String { rawValue }

    /// The built-in 8-bit melody: frequencies in Hz and durations in seconds. Empty means silent by default.
    var notes: [(frequency: Double, duration: Double)] {
        switch self {
        case .sessionStarted: return []
        case .attention: return [(659.25, 0.08), (880.0, 0.08), (659.25, 0.08), (880.0, 0.14)]
        case .question: return [(880.0, 0.08), (1174.66, 0.14)]
        case .done: return [(523.25, 0.07), (659.25, 0.07), (783.99, 0.07), (1046.5, 0.16)]
        case .error: return [(392.0, 0.1), (311.13, 0.18)]
        }
    }
}

@MainActor
final class AgentSoundPlayer {
    static let shared = AgentSoundPlayer()

    typealias Cue = AgentSoundCue

    private let sampleRate = 44_100.0
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var stopTask: Task<Void, Never>?

    func play(_ cue: Cue) {
        guard Defaults[.agentSoundsEnabled], !cue.notes.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = makeBuffer(cue, format: format)
        else { return }

        if engine == nil {
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            self.engine = engine
            self.player = player
        }
        guard let engine, let player else { return }

        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            return
        }
        player.scheduleBuffer(buffer)
        player.play()

        // Release the audio device shortly after the chime ends
        stopTask?.cancel()
        let duration = cue.notes.reduce(0) { $0 + $1.duration }
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration + 0.5))
            guard !Task.isCancelled else { return }
            self?.player?.stop()
            self?.engine?.stop()
        }
    }

    private func makeBuffer(_ cue: Cue, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let notes = cue.notes
        let totalFrames = notes.reduce(0) { $0 + Int($1.duration * sampleRate) }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)),
              let samples = buffer.floatChannelData?[0]
        else { return nil }

        let volume: Float = 0.12
        // Short fades at each end of a note avoid clicks
        let fadeFrames = Int(0.004 * sampleRate)
        var offset = 0
        for note in notes {
            let frames = Int(note.duration * sampleRate)
            let period = sampleRate / note.frequency
            for frame in 0..<frames {
                let phase = Double(frame).truncatingRemainder(dividingBy: period) / period
                let square: Float = phase < 0.5 ? 1 : -1
                let fade = Float(min(1, Double(min(frame, frames - frame)) / Double(fadeFrames)))
                samples[offset + frame] = square * volume * fade
            }
            offset += frames
        }
        buffer.frameLength = AVAudioFrameCount(totalFrames)
        return buffer
    }
}
