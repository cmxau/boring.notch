//
//  AgentSoundPlayer.swift
//  boringNotch
//
//  Short 8-bit chimes for agent events, synthesised as square waves.
//

import AVFoundation
import Defaults

@MainActor
final class AgentSoundPlayer {
    static let shared = AgentSoundPlayer()

    enum Cue {
        /// An agent needs a decision or an answer.
        case attention
        /// An agent finished its turn.
        case done

        /// Frequencies in Hz and durations in seconds.
        var notes: [(frequency: Double, duration: Double)] {
            switch self {
            case .attention: return [(659.25, 0.08), (880.0, 0.08), (659.25, 0.08), (880.0, 0.14)]
            case .done: return [(523.25, 0.07), (659.25, 0.07), (783.99, 0.07), (1046.5, 0.16)]
            }
        }
    }

    private let sampleRate = 44_100.0
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var stopTask: Task<Void, Never>?

    func play(_ cue: Cue) {
        guard Defaults[.agentSoundsEnabled],
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
