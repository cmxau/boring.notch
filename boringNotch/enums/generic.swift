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

/// What the home tab shows: two panes side by side, or music alone.
enum HomeLayout: String, CaseIterable, Identifiable, Defaults.Serializable {
    case musicCalendar = "Music + Calendar"
    case musicAgents = "Music + AI Agents"
    case calendarAgents = "Calendar + AI Agents"
    case music = "Music only"

    var id: String { rawValue }

    var panes: [NotchViews] {
        switch self {
        case .musicCalendar: return [.music, .calendar]
        case .musicAgents: return [.music, .agents]
        case .calendarAgents: return [.calendar, .agents]
        case .music: return [.music]
        }
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

enum SliderColorEnum: String, CaseIterable, Defaults.Serializable {
    case white = "White"
    case albumArt = "Match album art"
    case accent = "Accent color"
}
