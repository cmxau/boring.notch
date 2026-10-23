//
//  BoringNotchXPCHelperProtocol.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@objc protocol BoringNotchXPCHelperProtocol {
    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    func requestAccessibilityAuthorization()
    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
    // Keyboard backlight / CoreBrightness access (performed by the helper)
    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Screen brightness access (performed by the helper)
    func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // AI agent integrations: hook settings in the user's home folder, which the sandboxed app can't reach.
    // Paths are relative to the home folder and limited to the agents' own config files.
    func agentFileExists(_ path: String, with reply: @escaping (Bool) -> Void)
    func readAgentFile(_ path: String, with reply: @escaping (Data?) -> Void)
    func writeAgentFile(_ path: String, contents: Data, executable: Bool, with reply: @escaping (String?) -> Void)
    /// Names of the entries in an allowed folder, or nil if it can't be read.
    func listAgentDirectory(_ path: String, with reply: @escaping ([String]?) -> Void)
    // Jumping to the exact pane of an agent. `terminal` is "tmux", "kitty" or "wezterm"; the helper validates
    // `target` (pane or window ID) and `socket`, and builds the command itself.
    func focusTerminalPane(_ terminal: String, target: String, socket: String?, with reply: @escaping (Bool) -> Void)
    // Agents on remote servers: an SSH reverse tunnel per host, and the agents' hook files on that host.
    // `host` is an SSH destination (a ~/.ssh/config alias or user@host); paths are relative to the remote home
    // folder and limited to the same files as on this Mac.
    func startSSHTunnel(_ host: String, remotePort: Int, localPort: Int, with reply: @escaping (String?) -> Void)
    func stopSSHTunnel(_ host: String)
    /// Whether the tunnel is up, and the last thing ssh reported.
    func sshTunnelStatus(_ host: String, with reply: @escaping (Bool, String) -> Void)
    func remoteAgentFileExists(_ host: String, path: String, with reply: @escaping (Bool) -> Void)
    func readRemoteAgentFile(_ host: String, path: String, with reply: @escaping (Data?) -> Void)
    func writeRemoteAgentFile(_ host: String, path: String, contents: Data, executable: Bool, with reply: @escaping (String?) -> Void)
    func remoteHomeDirectory(_ host: String, with reply: @escaping (String?) -> Void)
    // Usage and quota. The helper reads Claude Code's sign-in from the keychain itself and returns only the
    // usage response, so the token never reaches the app.
    func fetchClaudeUsage(with reply: @escaping (Data?, String?) -> Void)
}

