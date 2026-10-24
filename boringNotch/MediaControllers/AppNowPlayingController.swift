//
//  AppNowPlayingController.swift
//  boringNotch
//
//  Players without a scripting interface (Amazon Music, SoundCloud) report to macOS Now Playing like any other
//  media app. This follows Now Playing but only for the chosen app, so another app playing doesn't take over the
//  notch, and controls are only sent while the chosen app is the one playing.
//

import AppKit
import Combine
import Foundation

final class AppNowPlayingController: ObservableObject, MediaControllerProtocol {
    private let base: NowPlayingController
    private let bundleIdentifiers: Set<String>
    private var cancellable: AnyCancellable?

    @Published private(set) var playbackState: PlaybackState

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    init?(bundleIdentifiers: Set<String>) {
        guard let base = NowPlayingController() else { return nil }
        self.base = base
        self.bundleIdentifiers = bundleIdentifiers

        var idle = PlaybackState(bundleIdentifier: bundleIdentifiers.sorted().first ?? "")
        idle.title = ""
        idle.artist = ""
        idle.album = ""
        playbackState = idle

        cancellable = base.playbackStatePublisher.sink { [weak self] state in
            guard let self else { return }
            if bundleIdentifiers.contains(state.bundleIdentifier) {
                self.playbackState = state
            } else if self.playbackState.isPlaying {
                // Another app took over Now Playing; the chosen app isn't playing any more
                self.playbackState.isPlaying = false
            }
        }
    }

    /// Whether the chosen app is the one macOS is reporting as playing.
    private var isChosenAppPlaying: Bool {
        bundleIdentifiers.contains(base.playbackState.bundleIdentifier)
    }

    var supportsVolumeControl: Bool { isChosenAppPlaying && base.supportsVolumeControl }
    var supportsFavorite: Bool { false }

    func setFavorite(_ favorite: Bool) async {}

    func play() async {
        guard isChosenAppPlaying else { return }
        await base.play()
    }

    func pause() async {
        guard isChosenAppPlaying else { return }
        await base.pause()
    }

    func seek(to time: Double) async {
        guard isChosenAppPlaying else { return }
        await base.seek(to: time)
    }

    func nextTrack() async {
        guard isChosenAppPlaying else { return }
        await base.nextTrack()
    }

    func previousTrack() async {
        guard isChosenAppPlaying else { return }
        await base.previousTrack()
    }

    func togglePlay() async {
        guard isChosenAppPlaying else { return }
        await base.togglePlay()
    }

    func toggleShuffle() async {
        guard isChosenAppPlaying else { return }
        await base.toggleShuffle()
    }

    func toggleRepeat() async {
        guard isChosenAppPlaying else { return }
        await base.toggleRepeat()
    }

    func setVolume(_ level: Double) async {
        guard isChosenAppPlaying else { return }
        await base.setVolume(level)
    }

    func isActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains { bundleIdentifiers.contains($0.bundleIdentifier ?? "") }
    }

    func updatePlaybackInfo() async {
        await base.updatePlaybackInfo()
    }
}
