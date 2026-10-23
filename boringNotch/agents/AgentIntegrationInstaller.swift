//
//  AgentIntegrationInstaller.swift
//  boringNotch
//
//  Adds Boring Notch's hooks to each AI agent's settings, so they report to the notch with no setup.
//  Only Boring Notch's own entries are added or removed; everything else in those files is left alone.
//

import Defaults
import Foundation
import os

@MainActor
final class AgentIntegrationInstaller: ObservableObject {
    static let shared = AgentIntegrationInstaller()

    enum Status: Equatable {
        /// The agent doesn't seem to be installed on this Mac.
        case agentNotFound
        case notConnected
        case connected
        case failed(String)
    }

    @Published private(set) var statuses: [AgentKind: Status] = [:]

    private let logger = Logger(subsystem: "com.theboringteam.boringnotch", category: "AgentIntegration")
    private let helper = XPCHelperClient.shared

    private static let bridgePath = ".boring-notch/bridge"
    private static let hookPath = ".boring-notch/bin/boring-agent-hook"
    /// Identifies Boring Notch's entries in the agents' settings.
    private static let marker = "boring-agent-hook"

    /// The real home folder, not the app's sandbox container.
    static var homeDirectory: String {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return String(cString: directory)
        }
        return NSHomeDirectory()
    }

    private static var hookExecutable: String {
        homeDirectory + "/" + hookPath
    }

    // MARK: - Bridge

    /// Writes the port and token the bridge script uses to reach the notch, and the script itself.
    func writeBridge(port: UInt16, token: String) async {
        if let script = Bundle.main.url(forResource: "boring-agent-hook", withExtension: "sh"),
           let contents = try? Data(contentsOf: script) {
            await writeIfChanged(Self.hookPath, contents, executable: true)
        }
        await writeIfChanged(Self.bridgePath, Data("port=\(port)\ntoken=\(token)\n".utf8))
    }

    // MARK: - Agents

    /// Connects every installed agent the user hasn't disconnected themselves.
    func installDetectedAgents() async {
        let disconnected = Set(Defaults[.agentIntegrationsDisconnected])
        for kind in AgentKind.allCases {
            guard await isAgentInstalled(kind) else {
                statuses[kind] = .agentNotFound
                continue
            }
            if disconnected.contains(kind.rawValue) {
                statuses[kind] = .notConnected
            } else {
                await connect(kind)
            }
        }
    }

    func refreshStatuses() async {
        let disconnected = Set(Defaults[.agentIntegrationsDisconnected])
        for kind in AgentKind.allCases {
            if !(await isAgentInstalled(kind)) {
                statuses[kind] = .agentNotFound
            } else if disconnected.contains(kind.rawValue) {
                statuses[kind] = .notConnected
            } else if case .failed = statuses[kind] {
                continue
            } else {
                statuses[kind] = .connected
            }
        }
    }

    func connect(_ kind: AgentKind) async {
        Defaults[.agentIntegrationsDisconnected].removeAll { $0 == kind.rawValue }
        statuses[kind] = await update(kind, install: true)
    }

    func disconnect(_ kind: AgentKind) async {
        if !Defaults[.agentIntegrationsDisconnected].contains(kind.rawValue) {
            Defaults[.agentIntegrationsDisconnected].append(kind.rawValue)
        }
        let status = await update(kind, install: false)
        statuses[kind] = status == .connected ? .notConnected : status
    }

    private func isAgentInstalled(_ kind: AgentKind) async -> Bool {
        await helper.agentFileExists(Self.configFolder(for: kind))
    }

    private func update(_ kind: AgentKind, install: Bool) async -> Status {
        let path = Self.configFile(for: kind)
        let existing = await helper.readAgentFile(path)
        do {
            let updated: Data
            switch kind {
            case .claudeCode:
                updated = try Self.updatedHooksJSON(existing, events: Self.claudeEvents, agent: kind, install: install)
            case .geminiCLI:
                updated = try Self.updatedHooksJSON(existing, events: Self.geminiEvents, agent: kind, install: install)
            case .codex:
                updated = try Self.updatedCodexConfig(existing, install: install)
            }
            if let error = await writeIfChanged(path, updated, previous: existing) {
                logger.error("Couldn't update \(path, privacy: .public): \(error, privacy: .public)")
                return .failed(error)
            }
            return install ? .connected : .notConnected
        } catch {
            logger.error("Couldn't update \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    @discardableResult
    private func writeIfChanged(_ path: String, _ contents: Data, executable: Bool = false, previous: Data? = nil) async -> String? {
        let current: Data?
        if let previous {
            current = previous
        } else {
            current = await helper.readAgentFile(path)
        }
        guard current != contents else { return nil }
        return await helper.writeAgentFile(path, contents: contents, executable: executable)
    }

    // MARK: - Settings formats

    private static func configFolder(for kind: AgentKind) -> String {
        switch kind {
        case .claudeCode: return ".claude"
        case .codex: return ".codex"
        case .geminiCLI: return ".gemini"
        }
    }

    private static func configFile(for kind: AgentKind) -> String {
        switch kind {
        case .claudeCode: return ".claude/settings.json"
        case .codex: return ".codex/config.toml"
        case .geminiCLI: return ".gemini/settings.json"
        }
    }

    private struct HookEvent {
        let name: String
        let matcher: String?
        /// In the agent's own unit: seconds for Claude Code, milliseconds for Gemini CLI.
        let timeout: Int
    }

    private static let claudeEvents: [HookEvent] = [
        HookEvent(name: "SessionStart", matcher: nil, timeout: 10),
        HookEvent(name: "SessionEnd", matcher: nil, timeout: 5),
        HookEvent(name: "UserPromptSubmit", matcher: nil, timeout: 10),
        // Questions wait in the notch; every other tool call returns within a few seconds
        HookEvent(name: "PreToolUse", matcher: "*", timeout: 86400),
        HookEvent(name: "PermissionRequest", matcher: "*", timeout: 86400),
        HookEvent(name: "Notification", matcher: "*", timeout: 10),
        HookEvent(name: "Stop", matcher: nil, timeout: 10),
    ]

    private static let geminiEvents: [HookEvent] = [
        HookEvent(name: "SessionStart", matcher: nil, timeout: 5000),
        HookEvent(name: "SessionEnd", matcher: nil, timeout: 5000),
        HookEvent(name: "BeforeAgent", matcher: nil, timeout: 5000),
        HookEvent(name: "BeforeTool", matcher: "*", timeout: 5000),
        HookEvent(name: "AfterTool", matcher: "*", timeout: 5000),
        HookEvent(name: "Notification", matcher: nil, timeout: 5000),
        HookEvent(name: "AfterAgent", matcher: nil, timeout: 5000),
    ]

    /// Shell command for a hook. It does nothing if Boring Notch has been removed, so the agent never errors.
    private static func hookCommand(agent: AgentKind, event: String) -> String {
        let script = shellQuoted(hookExecutable)
        return "test -x \(script) && \(script) \(agent.rawValue) \(event); exit 0"
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Adds or removes Boring Notch's hooks in a Claude Code or Gemini CLI settings.json, keeping everything else.
    private static func updatedHooksJSON(_ data: Data?, events: [HookEvent], agent: AgentKind, install: Bool) throws -> Data {
        var root: [String: Any] = [:]
        if let data, !data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw IntegrationError.unreadableSettings
            }
            root = parsed
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = (hooks[event.name] as? [[String: Any]] ?? []).compactMap(removingOwnHooks)
            if install {
                var handler: [String: Any] = [
                    "type": "command",
                    "command": hookCommand(agent: agent, event: event.name),
                    "timeout": event.timeout,
                ]
                if agent == .geminiCLI {
                    handler["name"] = "boring-notch"
                }
                var group: [String: Any] = ["hooks": [handler]]
                if let matcher = event.matcher {
                    group["matcher"] = matcher
                }
                groups.append(group)
            }
            hooks[event.name] = groups.isEmpty ? nil : groups
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks

        var data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        return data
    }

    /// A hook group without Boring Notch's handlers, or nil if nothing else was in it.
    private static func removingOwnHooks(_ group: [String: Any]) -> [String: Any]? {
        guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
        let others = handlers.filter { !(($0["command"] as? String)?.contains(marker) ?? false) }
        if others.count == handlers.count { return group }
        guard !others.isEmpty else { return nil }
        var group = group
        group["hooks"] = others
        return group
    }

    /// Adds or removes Boring Notch as Codex's `notify` program in config.toml.
    private static func updatedCodexConfig(_ data: Data?, install: Bool) throws -> Data {
        let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")

        // Top-level keys come before the first [table] header
        let firstTable = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.endIndex
        let notifyIndex = lines[..<firstTable].firstIndex {
            $0.trimmingCharacters(in: .whitespaces).range(of: #"^notify\s*="#, options: .regularExpression) != nil
        }

        if let notifyIndex {
            guard lines[notifyIndex].contains(marker) else {
                // Someone else's notify program; Codex only allows one
                if install { throw IntegrationError.codexNotifyInUse }
                return data ?? Data()
            }
            lines.remove(at: notifyIndex)
        }

        if install {
            // Codex appends the event JSON as the last argument, which the script receives as $1
            let script = "test -x \"$0\" && \"$0\" codex turn-complete \"$1\"; exit 0"
            let line = "notify = [\(tomlString("/bin/sh")), \(tomlString("-c")), \(tomlString(script)), \(tomlString(hookExecutable))] # \(marker)"
            lines.insert(line, at: 0)
        }

        var result = lines.joined(separator: "\n")
        if !result.isEmpty && !result.hasSuffix("\n") {
            result += "\n"
        }
        return Data(result.utf8)
    }

    private static func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    enum IntegrationError: LocalizedError {
        case unreadableSettings
        case codexNotifyInUse

        var errorDescription: String? {
            switch self {
            case .unreadableSettings:
                return "The settings file isn't valid JSON, so it was left untouched."
            case .codexNotifyInUse:
                return "Codex already runs another notify program, so it was left untouched."
            }
        }
    }
}
