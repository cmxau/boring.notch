//
//  AgentFileAllowlist.swift
//  BoringNotchXPCHelper
//
//  The only files and folders in the home folder (on this Mac, or on a remote server over SSH) that the helper
//  will touch on the app's behalf: the agents' hook settings and Boring Notch's own bridge files.
//  All paths are relative to the home folder.
//

import Foundation

enum AgentFileAllowlist {
    /// Files that can be read and written.
    static let files: Set<String> = [
        ".boring-notch/bridge",
        ".boring-notch/bin/boring-agent-hook",
        ".claude/settings.json",
        ".codex/config.toml",
        ".gemini/settings.json",
        ".gemini/config/hooks.json",
    ]

    /// Files that can only be read (for usage and quota tracking, for example).
    static let readOnlyFiles: Set<String> = []

    /// Folders whose existence can be checked, to see which agents are installed.
    static let folders: Set<String> = [
        ".claude",
        ".codex",
        ".gemini",
        ".gemini/antigravity",
        ".gemini/antigravity-cli",
        ".gemini/config",
    ]

    /// Folders whose contents can be listed and whose files (at any depth) can be read, but not written.
    static let readableFolders: Set<String> = []

    static func canCheck(_ path: String) -> Bool {
        isSafe(path) && (files.contains(path) || readOnlyFiles.contains(path) || folders.contains(path) || isInReadableFolder(path))
    }

    static func canRead(_ path: String) -> Bool {
        isSafe(path) && (files.contains(path) || readOnlyFiles.contains(path) || isInReadableFolder(path))
    }

    static func canWrite(_ path: String) -> Bool {
        isSafe(path) && files.contains(path)
    }

    static func canList(_ path: String) -> Bool {
        isSafe(path) && (readableFolders.contains(path) || isInReadableFolder(path))
    }

    private static func isInReadableFolder(_ path: String) -> Bool {
        readableFolders.contains { path.hasPrefix($0 + "/") }
    }

    /// Relative, with no `..` or `.` components, so it can't escape the folders above.
    private static func isSafe(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.hasPrefix("~")
            && !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == ".." || $0 == "." || $0.isEmpty }
    }
}
