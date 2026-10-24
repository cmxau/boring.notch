//
//  NotchPetView.swift
//  boringNotch
//
//  A cat that keeps the closed notch company while nothing else is showing. It goes through its routine
//  (resting, walking, playing with its tail, resting, walking, playing with a tennis ball) and naps until it's
//  clicked or has rested long enough.
//

import Combine
import ImageIO
import SwiftUI

enum NotchPetActivity: Equatable {
    case resting
    case walking
    case playingWithTail
    case playingWithBall

    /// The clip in boringNotch/pets.
    var clipName: String {
        switch self {
        case .resting: return "PetResting"
        case .walking: return "PetWalking"
        case .playingWithTail: return "PetPlayingWithTail"
        case .playingWithBall: return "PetPlayingWithBall"
        }
    }

    /// How many times the clip plays before the cat moves on.
    var loops: Int {
        switch self {
        case .resting: return 20
        case .walking: return 10
        case .playingWithTail: return 4
        case .playingWithBall: return 2
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .resting: return "Cat resting. Click to wake it up."
        case .walking: return "Cat walking"
        case .playingWithTail: return "Cat playing with its tail"
        case .playingWithBall: return "Cat playing with a tennis ball"
        }
    }
}

/// Where the cat is in its routine. Shared, so it carries on where it left off when the notch closes again.
@MainActor
final class NotchPetModel: ObservableObject {
    static let shared = NotchPetModel()

    static let routine: [NotchPetActivity] = [.resting, .walking, .playingWithTail, .resting, .walking, .playingWithBall]

    @Published private(set) var step = 0

    var activity: NotchPetActivity {
        Self.routine[step]
    }

    func advance() {
        step = (step + 1) % Self.routine.count
    }
}

/// The decoded frames of one pet clip.
struct NotchPetClip {
    let frames: [CGImage]
    /// Seconds each frame is shown.
    let durations: [Double]

    var duration: Double {
        durations.reduce(0, +)
    }

    /// Width over height of every clip (they share one canvas).
    static let aspectRatio: CGFloat = 100.0 / 84.0

    @MainActor private static var cache: [String: NotchPetClip] = [:]

    @MainActor
    static func named(_ name: String) -> NotchPetClip? {
        if let clip = cache[name] { return clip }
        guard let url = Bundle.main.url(forResource: name, withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }

        var frames: [CGImage] = []
        var durations: [Double] = []
        for index in 0..<CGImageSourceGetCount(source) {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
                ?? gif?[kCGImagePropertyGIFDelayTime] as? Double
                ?? 0.1
            frames.append(image)
            durations.append(max(delay, 0.02))
        }
        guard !frames.isEmpty else { return nil }
        let clip = NotchPetClip(frames: frames, durations: durations)
        cache[name] = clip
        return clip
    }
}

@MainActor
struct NotchPetView: View {
    /// Height of the pet; its width follows the clips' aspect ratio.
    let size: CGFloat
    /// Clicking the cat while it isn't resting does what clicking the notch does.
    var onOtherTap: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }

    @ObservedObject private var model = NotchPetModel.shared
    @State private var frameIndex = 0

    private var clip: NotchPetClip? {
        NotchPetClip.named(model.activity.clipName)
    }

    var body: some View {
        Group {
            if let clip, !clip.frames.isEmpty {
                Image(decorative: clip.frames[min(frameIndex, clip.frames.count - 1)], scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(width: size * NotchPetClip.aspectRatio, height: size)
        .contentShape(Rectangle())
        .onTapGesture {
            if model.activity == .resting {
                model.advance()
            } else {
                onOtherTap()
            }
        }
        .onHover(perform: onHover)
        // Plays the current clip
        .task(id: model.step) {
            frameIndex = 0
            guard let clip else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(clip.durations[frameIndex]))
                guard !Task.isCancelled else { return }
                frameIndex = (frameIndex + 1) % clip.frames.count
            }
        }
        // Moves on to the next activity once this one has played long enough
        .task(id: model.step) {
            guard let clip else { return }
            try? await Task.sleep(for: .seconds(clip.duration * Double(model.activity.loops)))
            guard !Task.isCancelled else { return }
            model.advance()
        }
        .accessibilityElement()
        .accessibilityLabel(model.activity.accessibilityDescription)
        .accessibilityAddTraits(model.activity == .resting ? .isButton : [])
    }
}
