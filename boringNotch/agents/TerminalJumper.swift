//
//  TerminalJumper.swift
//  boringNotch
//
//  Brings the terminal an agent is running in back to the front, down to the exact tab where the terminal
//  can be scripted.
//

import AppKit
import os

@MainActor
enum TerminalJumper {
    private static let logger = Logger(subsystem: "com.theboringteam.boringnotch", category: "TerminalJumper")

    /// `TERM_PROGRAM` values for terminals that don't otherwise identify their app.
    private static let programBundleIDs: [String: String] = [
        "Apple_Terminal": "com.apple.Terminal",
        "iTerm.app": "com.googlecode.iterm2",
        "ghostty": "com.mitchellh.ghostty",
        "WezTerm": "com.github.wez.wezterm",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "vscode": "com.microsoft.VSCode",
        "Hyper": "co.zeit.hyper",
        "Tabby": "org.tabby",
        "zed": "dev.zed.Zed",
    ]

    static func jump(to location: TerminalLocation) {
        guard let bundleID = bundleID(for: location) else {
            logger.notice("Don't know which app this agent is running in")
            return
        }

        if let tty = location.tty {
            switch bundleID {
            case "com.apple.Terminal":
                if run(terminalScript(tty: tty)) { return }
            case "com.googlecode.iterm2":
                if run(iTermScript(tty: tty)) { return }
            default:
                break
            }
        }
        activate(bundleID)
    }

    private static func bundleID(for location: TerminalLocation) -> String? {
        if let bundleID = location.appBundleID { return bundleID }
        if let program = location.program, let bundleID = programBundleIDs[program] { return bundleID }
        if location.kittyWindow != nil { return "net.kovidgoyal.kitty" }
        if location.weztermPane != nil { return "com.github.wez.wezterm" }
        return nil
    }

    private static func activate(_ bundleID: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - AppleScript

    private static func devicePath(_ tty: String) -> String {
        let path = tty.hasPrefix("/dev/") ? tty : "/dev/" + tty
        // Only ever interpolated into a script as a quoted string, so keep it to characters a tty name can have
        return String(path.filter { $0.isLetter || $0.isNumber || $0 == "/" })
    }

    private static func terminalScript(tty: String) -> String {
        """
        tell application "Terminal"
            repeat with theWindow in windows
                repeat with theTab in tabs of theWindow
                    if tty of theTab is "\(devicePath(tty))" then
                        set selected of theTab to true
                        set index of theWindow to 1
                    end if
                end repeat
            end repeat
            activate
        end tell
        """
    }

    private static func iTermScript(tty: String) -> String {
        """
        tell application "iTerm2"
            repeat with theWindow in windows
                repeat with theTab in tabs of theWindow
                    repeat with theSession in sessions of theTab
                        if tty of theSession is "\(devicePath(tty))" then
                            select theWindow
                            tell theTab to select
                            tell theSession to select
                        end if
                    end repeat
                end repeat
            end repeat
            activate
        end tell
        """
    }

    private static func run(_ source: String) -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            logger.notice("Couldn't select the terminal tab: \(error, privacy: .public)")
            return false
        }
        return true
    }
}
