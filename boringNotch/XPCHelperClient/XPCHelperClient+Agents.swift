//
//  XPCHelperClient+Agents.swift
//  boringNotch
//
//  The helper calls behind the AI agents integration: hook settings, terminal panes, SSH servers and usage.
//

import Foundation

extension XPCHelperClient {
    private func call<T>(_ fallback: T, _ body: @escaping (BoringNotchXPCHelperProtocol, CheckedContinuation<T, Error>) -> Void) async -> T {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation(body)
        } catch {
            return fallback
        }
    }

    // MARK: - Files on this Mac

    nonisolated func agentFileExists(_ path: String) async -> Bool {
        await call(false) { service, continuation in
            service.agentFileExists(path) { continuation.resume(returning: $0) }
        }
    }

    nonisolated func readAgentFile(_ path: String) async -> Data? {
        await call(nil) { service, continuation in
            service.readAgentFile(path) { continuation.resume(returning: $0) }
        }
    }

    /// Writes one of the agents' hook files. Returns an error message, or nil on success.
    nonisolated func writeAgentFile(_ path: String, contents: Data, executable: Bool = false) async -> String? {
        await call("Boring Notch's helper isn't available") { service, continuation in
            service.writeAgentFile(path, contents: contents, executable: executable) { continuation.resume(returning: $0) }
        }
    }

    nonisolated func listAgentDirectory(_ path: String) async -> [String]? {
        await call(nil) { service, continuation in
            service.listAgentDirectory(path) { continuation.resume(returning: $0) }
        }
    }

    // MARK: - Terminal panes

    /// Focuses a tmux, kitty or WezTerm pane. `terminal` is "tmux", "kitty" or "wezterm".
    nonisolated func focusTerminalPane(_ terminal: String, target: String, socket: String?) async -> Bool {
        await call(false) { service, continuation in
            service.focusTerminalPane(terminal, target: target, socket: socket) { continuation.resume(returning: $0) }
        }
    }

    // MARK: - Remote servers

    /// Returns an error message, or nil once the tunnel has started.
    nonisolated func startSSHTunnel(_ host: String, remotePort: Int, localPort: Int) async -> String? {
        await call("Boring Notch's helper isn't available") { service, continuation in
            service.startSSHTunnel(host, remotePort: remotePort, localPort: localPort) { continuation.resume(returning: $0) }
        }
    }

    nonisolated func stopSSHTunnel(_ host: String) async {
        await call(()) { service, continuation in
            service.stopSSHTunnel(host)
            continuation.resume(returning: ())
        }
    }

    nonisolated func sshTunnelStatus(_ host: String) async -> (isRunning: Bool, message: String) {
        await call((false, "")) { service, continuation in
            service.sshTunnelStatus(host) { continuation.resume(returning: ($0, $1)) }
        }
    }

    nonisolated func remoteAgentFileExists(_ host: String, path: String) async -> Bool {
        await call(false) { service, continuation in
            service.remoteAgentFileExists(host, path: path) { continuation.resume(returning: $0) }
        }
    }

    nonisolated func readRemoteAgentFile(_ host: String, path: String) async -> Data? {
        await call(nil) { service, continuation in
            service.readRemoteAgentFile(host, path: path) { continuation.resume(returning: $0) }
        }
    }

    /// Returns an error message, or nil on success.
    nonisolated func writeRemoteAgentFile(_ host: String, path: String, contents: Data, executable: Bool = false) async -> String? {
        await call("Boring Notch's helper isn't available") { service, continuation in
            service.writeRemoteAgentFile(host, path: path, contents: contents, executable: executable) { continuation.resume(returning: $0) }
        }
    }

    nonisolated func remoteHomeDirectory(_ host: String) async -> String? {
        await call(nil) { service, continuation in
            service.remoteHomeDirectory(host) { continuation.resume(returning: $0) }
        }
    }

    // MARK: - Usage

    /// Claude Code's usage response, or an error message.
    nonisolated func fetchClaudeUsage() async -> (data: Data?, error: String?) {
        await call((nil, "Boring Notch's helper isn't available")) { service, continuation in
            service.fetchClaudeUsage { continuation.resume(returning: ($0, $1)) }
        }
    }
}
