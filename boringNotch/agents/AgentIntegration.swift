//
//  AgentIntegration.swift
//  boringNotch
//
//  What it takes to support an AI agent: how to tell it's installed, how to add Boring Notch's hooks to its
//  settings, and how to turn its hook events into sessions and decisions. Each agent is one type conforming to
//  `AgentIntegration`, listed in `AgentRegistry`.
//

import Foundation

/// One hook event from an agent, as posted by the bridge script.
struct AgentEvent {
    /// The event name the hook was registered with, e.g. "PermissionRequest".
    let name: String
    /// The hook's JSON payload, or empty if it wasn't a JSON object.
    let payload: [String: Any]
    let rawBody: Data
    let terminal: TerminalLocation
    /// Fires if the agent stops waiting for an answer.
    let cancellation: AgentRequestCancellation

    /// Session ID unique across agents and hosts, from the agent's own session ID.
    func sessionID(for kind: AgentKind, _ agentSessionID: String?) -> String {
        [kind.id, terminal.remoteHost, agentSessionID ?? "default"].compactMap { $0 }.joined(separator: ":")
    }

    func string(_ key: String) -> String? {
        payload[key] as? String
    }

    func object(_ key: String) -> [String: Any] {
        payload[key] as? [String: Any] ?? [:]
    }
}

@MainActor
protocol AgentIntegration {
    var kind: AgentKind { get }

    /// Home-relative paths; the agent counts as installed if any of them exists.
    /// Each must be in the helper's allowlist (`AgentFileAllowlist`).
    var detectionPaths: [String] { get }

    /// Home-relative config files this integration edits. Each must be in the helper's allowlist.
    var configFiles: [String] { get }

    /// New contents for the config files, given their current contents (missing files are absent from
    /// `current`). Returns only the files to write. Must only add or remove Boring Notch's own entries
    /// (identified by `AgentHookCommand.marker`) and leave everything else as it was.
    /// - Parameter hookExecutable: Absolute path of the bridge script to put in the hook commands. It's
    ///   `AgentHookCommand.executable` on this Mac, and the remote path when deploying over SSH.
    func updatedConfigFiles(_ current: [String: Data], install: Bool, hookExecutable: String) throws -> [String: Data]

    /// Handles one hook event. The returned data is printed by the bridge script as the hook's output;
    /// return empty data to leave the agent's own behaviour unchanged.
    func handle(_ event: AgentEvent, hub: AgentHub) async -> Data
}

enum AgentIntegrationError: LocalizedError {
    case unreadableSettings(String)
    case conflictingSetting(String)

    var errorDescription: String? {
        switch self {
        case .unreadableSettings(let file):
            return "\(file) couldn't be read, so it was left untouched."
        case .conflictingSetting(let message):
            return message
        }
    }
}

// MARK: - Hook commands

/// Builds the commands agents run to reach the bridge script.
enum AgentHookCommand {
    /// Present in every hook entry Boring Notch adds, so its entries can be found and removed again.
    static let marker = "boring-agent-hook"

    /// How long the bridge script waits for the notch to answer.
    enum Wait {
        /// Report and return within a few seconds. For events that only update status.
        case never
        /// Wait until the notch decides. For events that ask for permission.
        case always
        /// Wait only when the event's tool (`tool_name`, or Antigravity's `toolCall.name`) is one of these;
        /// otherwise return quickly.
        case forTools([String])

        var environment: String? {
            switch self {
            case .never: return nil
            case .always: return "BORING_NOTCH_WAIT=always"
            case .forTools(let tools): return "BORING_NOTCH_WAIT=tools:" + tools.joined(separator: ",")
            }
        }
    }

    /// The real home folder, not the app's sandbox container.
    static var homeDirectory: String {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return String(cString: directory)
        }
        return NSHomeDirectory()
    }

    static let scriptPath = ".boring-notch/bin/boring-agent-hook"

    static var executable: String {
        homeDirectory + "/" + scriptPath
    }

    /// A shell command line for agents that run hooks through a shell. It does nothing (and succeeds) if
    /// Boring Notch has been removed, so the agent never reports a hook error.
    static func shell(agent: String, event: String, wait: Wait = .never, executable: String = executable) -> String {
        let script = shellQuoted(executable)
        let environment = wait.environment.map { $0 + " " } ?? ""
        return "test -x \(script) && \(environment)\(script) \(agent) \(event); exit 0"
    }

    /// An argument vector for agents that run hooks without a shell and append the payload as the last
    /// argument (Codex's `notify`, for example).
    static func argv(agent: String, event: String, wait: Wait = .never, executable: String = executable) -> [String] {
        let environment = wait.environment.map { "export \($0); " } ?? ""
        return ["/bin/sh", "-c", "\(environment)test -x \"$0\" && \"$0\" \(agent) \(event) \"$1\"; exit 0", executable]
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - JSON hook settings

/// Edits settings files that use Claude Code's hook layout, which several agents share:
/// `{"hooks": {"<Event>": [{"matcher": "...", "hooks": [{"type": "command", "command": "...", "timeout": N}]}]}}`.
enum JSONHookSettings {
    struct Event {
        let name: String
        let matcher: String?
        /// In the agent's own unit (seconds for Claude Code, milliseconds for Gemini CLI, ...).
        let timeout: Int?
        let wait: AgentHookCommand.Wait

        init(_ name: String, matcher: String? = nil, timeout: Int? = nil, wait: AgentHookCommand.Wait = .never) {
            self.name = name
            self.matcher = matcher
            self.timeout = timeout
            self.wait = wait
        }
    }

    /// Adds or removes Boring Notch's hooks, keeping everything else.
    /// - Parameters:
    ///   - hooksKey: Key path to the hooks object, e.g. `["hooks"]`.
    ///   - extraFields: Extra fields for each hook handler, e.g. `["name": "boring-notch"]`.
    static func updated(
        _ data: Data?,
        file: String,
        agent: String,
        events: [Event],
        install: Bool,
        hookExecutable: String = AgentHookCommand.executable,
        hooksKey: String = "hooks",
        extraFields: [String: Any] = [:]
    ) throws -> Data {
        var root = try parseObject(data, file: file)

        var hooks = root[hooksKey] as? [String: Any] ?? [:]
        for event in events {
            var groups = (hooks[event.name] as? [[String: Any]] ?? []).compactMap(removingOwnHandlers)
            if install {
                var handler: [String: Any] = [
                    "type": "command",
                    "command": AgentHookCommand.shell(agent: agent, event: event.name, wait: event.wait, executable: hookExecutable),
                ]
                if let timeout = event.timeout {
                    handler["timeout"] = timeout
                }
                handler.merge(extraFields) { current, _ in current }
                var group: [String: Any] = ["hooks": [handler]]
                if let matcher = event.matcher {
                    group["matcher"] = matcher
                }
                groups.append(group)
            }
            hooks[event.name] = groups.isEmpty ? nil : groups
        }
        root[hooksKey] = hooks.isEmpty ? nil : hooks
        return try serialize(root)
    }

    /// The JSON object in `data`; empty for a missing or blank file.
    static func parseObject(_ data: Data?, file: String) throws -> [String: Any] {
        guard let data, !data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) else { return [:] }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AgentIntegrationError.unreadableSettings(file)
        }
        return object
    }

    static func serialize(_ object: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }

    /// A hook group without Boring Notch's handlers, or nil if nothing else was in it.
    static func removingOwnHandlers(_ group: [String: Any]) -> [String: Any]? {
        guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
        let others = handlers.filter { !isOwn($0) }
        if others.count == handlers.count { return group }
        guard !others.isEmpty else { return nil }
        var group = group
        group["hooks"] = others
        return group
    }

    static func isOwn(_ handler: [String: Any]) -> Bool {
        (handler["command"] as? String)?.contains(AgentHookCommand.marker) ?? false
    }
}

// MARK: - Formatting

enum AgentFormatting {
    /// One line for the session list, e.g. "Bash: npm test" or "Edit: ContentView.swift".
    static func activity(tool: String, input: [String: Any]) -> String {
        guard !tool.isEmpty else { return "Working" }
        let target: String?
        if let path = input["file_path"] as? String ?? input["notebook_path"] as? String
            ?? input["absolute_path"] as? String ?? input["path"] as? String {
            target = (path as NSString).lastPathComponent
        } else {
            target = input["command"] as? String
                ?? input["cmd"] as? String
                ?? input["url"] as? String
                ?? input["query"] as? String
                ?? input["pattern"] as? String
                ?? input["description"] as? String
        }
        guard let target, !target.isEmpty else { return tool }
        return "\(tool): \(firstLine(target))"
    }

    /// What's worth showing when asking for permission: the full command, path or URL.
    static func detail(tool: String, input: [String: Any]) -> String {
        if let command = input["command"] as? String { return command }
        if let command = input["command"] as? [String] { return command.joined(separator: " ") }
        if let command = input["cmd"] as? String { return command }
        if let path = input["file_path"] as? String ?? input["notebook_path"] as? String ?? input["path"] as? String { return path }
        if let url = input["url"] as? String { return url }
        return prettyJSON(input) ?? tool
    }

    static func prettyJSON(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return String(text.prefix(1000))
    }

    static func firstLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return String(line.prefix(200))
    }

    /// JSON for a hook's output.
    static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])) ?? Data()
    }
}
