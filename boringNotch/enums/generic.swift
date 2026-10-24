//
//  generic.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Foundation
import Defaults

public enum Style {
    case notch
    case floating
}

public enum ContentType: Int, Codable, Hashable, Equatable {
    case normal
    case menu
    case settings
}

public enum NotchState {
    case closed
    case open
}

public enum NotchViews: String, CaseIterable, Defaults.Serializable {
    case home
    case music
    case calendar
    case agents
    case shelf

    var title: String {
        switch self {
        case .home: return "Home"
        case .music: return "Music"
        case .calendar: return "Calendar"
        case .agents: return "AI Agents"
        case .shelf: return "Shelf"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .agents: return "sparkles"
        case .shelf: return "tray.fill"
        }
    }
}

/// One half of the home tab.
enum HomePane: String, CaseIterable, Identifiable, Defaults.Serializable {
    case none = "None"
    case music = "Music"
    case calendar = "Calendar"
    case agents = "AI Agents"

    var id: String { rawValue }

    var view: NotchViews? {
        switch self {
        case .none: return nil
        case .music: return .music
        case .calendar: return .calendar
        case .agents: return .agents
        }
    }

    /// The home tab's panes, left to right. One chosen pane fills the whole width; none at all shows music.
    static var homePanes: [NotchViews] {
        let panes = [Defaults[.homeLeftPane], Defaults[.homeRightPane]].compactMap(\.view)
        return panes.isEmpty ? [.music] : panes
    }
}

enum SettingsEnum {
    case general
    case about
    case charge
    case download
    case mediaPlayback
    case hud
    case shelf
    case extensions
}

enum DownloadIndicatorStyle: String, Defaults.Serializable {
    case progress = "Progress"
    case percentage = "Percentage"
}

enum DownloadIconStyle: String, Defaults.Serializable {
    case onlyAppIcon = "Only app icon"
    case onlyIcon = "Only download icon"
    case iconAndAppIcon = "Icon and app icon"
}

enum WindowHeightMode: String, Defaults.Serializable {
    case matchMenuBar = "Match menubar height"
    case matchRealNotchSize = "Match real notch height"
    case custom = "Custom height"
}

