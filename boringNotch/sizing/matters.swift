//
//  sizeMatters.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = 20

/// This fork's GitHub pages.
enum AppLinks {
    static let repository = URL(string: "https://github.com/cmxau/boring.notch")!
    static let reportBug = URL(string: "https://github.com/cmxau/boring.notch/issues/new")!
}
/// The widest the open notch gets, and its height. Its width follows the closed notch; see `openNotchWidth`.
let openNotchSize: CGSize = .init(width: 640, height: 190)
/// How much wider the open notch is than the closed notch while music plays, so the header keeps the tabs on the
/// left of the camera and the buttons on the right, and the home view's halves stay readable.
let openNotchExtraWidth: CGFloat = 170
let windowSize: CGSize = .init(width: openNotchSize.width, height: openNotchSize.height + shadowPadding)
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 24), closed: (top: 6, bottom: 14))

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13.0, closed: 4.0)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

@MainActor func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }
    
    if let screen = selectedScreen {
        return screen.frame
    }
    
    return nil
}

/// Width of one tab button in the open notch's header.
let openNotchTabWidth: CGFloat = 24

/// The open notch's width: the closed notch with music playing (album art, camera, equaliser) plus
/// `openNotchExtraWidth`, or wider when the tabs need more room beside the camera.
func openNotchWidth(closedNotchSize: CGSize, closedNotchHeight: CGFloat, tabCount: Int) -> CGFloat {
    let closedMusicWidth = closedNotchSize.width + 2 * max(0, closedNotchHeight - 12) + 20
    // Tabs sit left of the camera, mirrored by the same width on the right; 62 is the open notch's side padding
    let fitsTabs = closedNotchSize.width + 2 * (CGFloat(tabCount) * openNotchTabWidth + 8) + 62
    return min(openNotchSize.width, max(closedMusicWidth + openNotchExtraWidth, fitsTabs))
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    // Check if the screen is available
    if let screen = selectedScreen {
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            // This is a display WITH a notch - use notch height settings
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        } else {
            // This is a display WITHOUT a notch - use non-notch height settings
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
