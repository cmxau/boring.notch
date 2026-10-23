//
//  AccessoryIndicatorView.swift
//  boringNotch
//
//  Artwork for the accessory that just connected: a looping clip for AirPods, an SF Symbol otherwise.
//

import AVFoundation
import SwiftUI
import VideoToolbox

struct AccessoryArtworkView: View {
    let artwork: AccessoryArtwork
    let size: CGFloat

    @State private var appeared = false

    var body: some View {
        Group {
            switch artwork {
            case .video(let name, let fallbackSymbol):
                if let url = Bundle.main.url(forResource: name, withExtension: "mp4") {
                    LoopingVideoView(url: url)
                } else {
                    Image(systemName: fallbackSymbol)
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.2)
                        .foregroundStyle(.white)
                }
            case .symbol(let name):
                Image(systemName: name)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.2)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(appeared ? 1 : 0.4)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                appeared = true
            }
        }
    }
}

/// Plays a muted, looping clip by drawing its frames as SwiftUI images, so the notch's clipping, scaling
/// and opacity animations apply to it like any other view (an AVPlayerLayer would sit outside of them).
struct LoopingVideoView: View {
    let url: URL

    @StateObject private var playback = LoopingVideoPlayback()

    var body: some View {
        TimelineView(.animation) { timeline in
            if let frame = playback.frame(at: timeline.date) {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Color.black
            }
        }
        .onAppear { playback.play(url) }
        .onDisappear { playback.stop() }
    }
}

@MainActor
final class LoopingVideoPlayback: ObservableObject {
    private let player = AVPlayer()
    private var output: AVPlayerItemVideoOutput?
    private var loopObserver: NSObjectProtocol?
    private var currentURL: URL?
    private var lastFrame: CGImage?

    init() {
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .none
    }

    func play(_ url: URL) {
        if currentURL != url {
            currentURL = url
            lastFrame = nil

            let item = AVPlayerItem(url: url)
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ])
            item.add(output)
            self.output = output
            player.replaceCurrentItem(with: item)

            if let loopObserver {
                NotificationCenter.default.removeObserver(loopObserver)
            }
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.player.seek(to: .zero)
                }
            }
        } else {
            player.seek(to: .zero)
        }
        player.play()
    }

    func stop() {
        player.pause()
    }

    /// The video frame for the display refresh at `date`, or the last one if no new frame is due.
    func frame(at date: Date) -> CGImage? {
        guard let output else { return lastFrame }
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: itemTime),
              let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        else { return lastFrame }

        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        if let image {
            lastFrame = image
        }
        return lastFrame
    }

    deinit {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        AccessoryArtworkView(artwork: .video("airpods-pro-2"), size: 40)
        AccessoryArtworkView(artwork: .video("airpods-max-sky-blue"), size: 40)
        AccessoryArtworkView(artwork: .video("ps5-controller", fallbackSymbol: "gamecontroller.fill"), size: 40)
        AccessoryArtworkView(artwork: .symbol("keyboard.fill"), size: 40)
    }
    .padding()
    .background(.black)
}
