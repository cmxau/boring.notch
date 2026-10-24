//
//  NotchBackgroundView.swift
//  boringNotch
//
//  What the open notch is drawn on: solid black, or liquid glass that blurs the wallpaper and windows behind
//  it. The closed notch always stays black so it blends with the camera housing.
//

import AppKit
import Defaults
import SwiftUI

enum NotchBackgroundStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case black = "Black"
    case liquidGlass = "Liquid Glass"

    var id: String { rawValue }
}

struct NotchBackgroundView: View {
    let isOpen: Bool
    @Default(.notchBackgroundStyle) private var style

    var body: some View {
        if isOpen && style == .liquidGlass {
            LiquidGlassBackground()
        } else {
            Color.black
        }
    }
}

/// Liquid glass on macOS 26, and a dark blur of what's behind the window before that.
private struct LiquidGlassBackground: View {
    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(.black.opacity(0.35)), in: Rectangle())
        } else {
            BehindWindowBlur()
        }
        #else
        BehindWindowBlur()
        #endif
    }
}

private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
