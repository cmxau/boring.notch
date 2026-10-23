//
//  LockScreenAnimation.swift
//  boringNotch
//
//  Padlock shown beside the notch while the Mac is locked, which pops open when it's unlocked,
//  similar to the Face ID unlock on iPhone.
//

import SwiftUI

enum LockScreenIndicatorState {
    case hidden
    case locked
    case unlocked
}

struct LockScreenAnimation: View {
    var isUnlocked: Bool
    /// Side length of the padlock artwork. The icons are drawn on a square canvas with built-in padding.
    var size: CGFloat

    private enum Phase {
        /// Whole closed padlock.
        case locked
        /// Body and shackles drawn as separate layers while the shackle pops open.
        case opening
        /// Whole open padlock.
        case unlocked
    }

    // Geometry of the 144px artwork, as fractions of the canvas
    /// Where the body starts. Everything above it is shackle.
    private let bodyTop: CGFloat = 61 / 144
    /// How far right the open artwork sits so its body lines up with the closed one.
    private let openBodyOffset: CGFloat = 20 / 144
    /// In the open artwork, everything right of this is the free shackle leg.
    private let openShackleLegX: CGFloat = 90 / 144
    /// How far the shackle lifts before it swings open.
    private let shackleLift: CGFloat = 10 / 144

    @State private var phase: Phase = .locked
    @State private var closedShackleLift: CGFloat = 0
    @State private var closedShackleOpacity: Double = 1
    @State private var openShackleLift: CGFloat = 0
    @State private var openShackleOpacity: Double = 0
    @State private var scale: CGFloat = 1
    @State private var appeared = false
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch phase {
            case .locked:
                artwork("LockClosed")
            case .opening:
                // Body
                artwork("LockClosed")
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: size * (1 - bodyTop))
                    }

                // Closed shackle
                artwork("LockClosed")
                    .mask(alignment: .top) {
                        Rectangle().frame(height: size * bodyTop)
                    }
                    .offset(y: -closedShackleLift * size)
                    .opacity(closedShackleOpacity)

                // Open shackle
                artwork("LockOpen")
                    .mask(alignment: .topLeading) {
                        ZStack(alignment: .topLeading) {
                            Rectangle().frame(height: size * bodyTop)
                            Rectangle()
                                .frame(width: size * (1 - openShackleLegX))
                                .offset(x: size * openShackleLegX)
                        }
                        .frame(width: size, height: size, alignment: .topLeading)
                    }
                    .offset(x: openBodyOffset * size, y: -openShackleLift * size)
                    .opacity(openShackleOpacity)
            case .unlocked:
                artwork("LockOpen")
                    .offset(x: openBodyOffset * size)
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .scaleEffect(scale * (appeared ? 1 : 0.4))
        .opacity(appeared ? 1 : 0)
        .accessibilityLabel(isUnlocked ? "Unlocked" : "Locked")
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                appeared = true
            }
            if isUnlocked {
                unlock()
            }
        }
        .onChange(of: isUnlocked) { _, unlocked in
            if unlocked {
                unlock()
            } else {
                reset()
            }
        }
        .onDisappear {
            animationTask?.cancel()
        }
    }

    private func artwork(_ name: String) -> some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }

    private func reset() {
        animationTask?.cancel()
        withAnimation(.smooth(duration: 0.25)) {
            phase = .locked
            closedShackleLift = 0
            closedShackleOpacity = 1
            openShackleLift = 0
            openShackleOpacity = 0
            scale = 1
        }
    }

    private func unlock() {
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            phase = .opening
            closedShackleLift = 0
            closedShackleOpacity = 1
            openShackleLift = shackleLift
            openShackleOpacity = 0

            // Give the lock screen a moment to start fading away so the pop is visible
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }

            // Lift the shackle out of the body
            withAnimation(.easeOut(duration: 0.16)) {
                closedShackleLift = shackleLift
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                scale = 1.15
            }
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }

            // Swing it open and let it drop into place with a little bounce
            withAnimation(.easeOut(duration: 0.12)) {
                closedShackleOpacity = 0
                openShackleOpacity = 1
            }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.5)) {
                openShackleLift = 0
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.05)) {
                scale = 1
            }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }

            phase = .unlocked
        }
    }
}

#Preview {
    struct PreviewContainer: View {
        @State private var unlocked = false

        var body: some View {
            VStack(spacing: 20) {
                LockScreenAnimation(isUnlocked: unlocked, size: 48)
                    .frame(width: 80, height: 60)
                    .background(.black)
                Button(unlocked ? "Lock" : "Unlock") { unlocked.toggle() }
            }
            .padding()
        }
    }
    return PreviewContainer()
}
