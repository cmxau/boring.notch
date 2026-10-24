//
//  AntigravityIntegration.swift
//  boringNotch
//
//  Google Antigravity: the IDE, the desktop app and the agy CLI, which all read the user-global hooks in
//  ~/.gemini/config/hooks.json. Terminal commands wait in the notch for approval; Allow and Deny answer
//  Antigravity's PreToolUse hook, and Terminal hands the call back to Antigravity's own prompt.
//
//  Antigravity's hooks file is keyed by hook name, and it decodes hook output strictly, so every handler always
//  prints a JSON object (`{}` when there's nothing to say) and PreToolUse replies carry only `decision` and
//  `reason`.
//

import Foundation

struct AntigravityIntegration: AgentIntegration {
    let kind = AgentKind(
        id: "antigravity",
        displayName: "Antigravity",
        symbol: "atom",
        capabilities: [.status, .approvals]
    )

    private let hooksFile = ".gemini/config/hooks.json"
    /// Boring Notch's entry in the hooks file.
    private let hookName = "boring-notch"
    /// Tools that wait for a decision in the notch. Everything else only updates the session's status.
    private let approvalTools = ["run_command"]

    var detectionPaths: [String] { [".gemini/antigravity", ".gemini/antigravity-cli", ".gemini/config"] }
    var configFiles: [String] { [hooksFile] }

    func updatedConfigFiles(_ current: [String: Data], install: Bool, hookExecutable: String) throws -> [String: Data] {
        var root = try JSONHookSettings.parseObject(current[hooksFile], file: hooksFile)

        if let existing = root[hookName] {
            // Only replace an entry Boring Notch wrote
            let isOwn = (try? JSONSerialization.data(withJSONObject: existing, options: [.fragmentsAllowed]))
                .flatMap { String(data: $0, encoding: .utf8) }?
                .contains(AgentHookCommand.marker) ?? false
            guard isOwn else {
                if install {
                    throw AgentIntegrationError.conflictingSetting("\(hooksFile) already has a hook called \"\(hookName)\", so it was left untouched.")
                }
                return [:]
            }
            root[hookName] = nil
        } else if !install {
            return [:]
        }

        if install {
            func handler(_ event: String, timeout: Int, wait: AgentHookCommand.Wait = .never) -> [String: Any] {
                ["type": "command", "command": command(event: event, wait: wait, executable: hookExecutable), "timeout": timeout]
            }
            // Timeouts are in seconds. Tool events take matcher groups; the others take handlers directly.
            root[hookName] = [
                "enabled": true,
                "SessionStart": [handler("SessionStart", timeout: 10)],
                "PreInvocation": [handler("PreInvocation", timeout: 10)],
                "PreToolUse": [["matcher": "*", "hooks": [handler("PreToolUse", timeout: 86400, wait: .forTools(approvalTools))]] as [String: Any]],
                "PostToolUse": [["matcher": "*", "hooks": [handler("PostToolUse", timeout: 10)]] as [String: Any]],
                "Stop": [handler("Stop", timeout: 10)],
            ] as [String: Any]
        }
        return [hooksFile: try JSONHookSettings.serialize(root)]
    }

    /// Like `AgentHookCommand.shell`, but prints `{}` when the notch has no answer, because Antigravity treats
    /// output that isn't a JSON object as a failed hook (and a failed PreToolUse hook blocks the tool call).
    private func command(event: String, wait: AgentHookCommand.Wait, executable: String) -> String {
        let script = AgentHookCommand.shellQuoted(executable)
        let environment = wait.environment.map { $0 + " " } ?? ""
        return "out=\"$(test -x \(script) && \(environment)\(script) \(kind.id) \(event))\"; [ -n \"$out\" ] || out='{}'; printf '%s\\n' \"$out\"; exit 0"
    }

    func handle(_ event: AgentEvent, hub: AgentHub) async -> Data {
        let empty = AgentFormatting.json([:])
        let id = event.sessionID(for: kind, event.string("conversationId"))
        let cwd = (event.payload["workspacePaths"] as? [String])?.first ?? event.string("cwd") ?? ""
        let toolCall = event.object("toolCall")
        let tool = Self.toolName(toolCall["name"] as? String ?? "")
        let input = Self.toolInput(toolCall["args"])

        func update(_ change: (inout AgentSession) -> Void) {
            hub.updateSession(id: id, kind: kind, cwd: cwd, terminal: event.terminal, change)
        }

        switch event.name {
        case "SessionStart":
            update { $0.status = .idle }

        case "PreInvocation":
            update {
                if !$0.status.needsAttention {
                    $0.status = .working
                }
            }

        case "PreToolUse":
            guard approvalTools.contains(toolCall["name"] as? String ?? "") else {
                update {
                    $0.status = .working
                    $0.activity = AgentFormatting.activity(tool: tool, input: input)
                }
                return empty
            }

            update {
                $0.status = .waitingForApproval
                $0.activity = AgentFormatting.activity(tool: tool, input: input)
            }
            let request = AgentRequest.Kind.permission(tool: tool, detail: AgentFormatting.detail(tool: tool, input: input))
            let decision = await hub.awaitDecision(request, sessionID: id, agent: kind, cancellation: event.cancellation)
            hub.resumeWorking(id)

            switch decision {
            case .allow:
                return AgentFormatting.json(["decision": "allow"])
            case .deny(let message):
                let reason = message.flatMap { $0.isEmpty ? nil : $0 } ?? "Denied in Boring Notch"
                return AgentFormatting.json(["decision": "deny", "reason": reason])
            case .answers, .handBack:
                // Antigravity's own prompt decides
                return AgentFormatting.json(["decision": "ask"])
            }

        case "PostToolUse":
            update {
                if !$0.status.needsAttention {
                    $0.status = .working
                }
            }

        case "Stop":
            update {
                $0.status = .finished
                $0.activity = nil
                if let message = event.string("lastAssistantMessage") ?? event.string("response") {
                    $0.lastMessage = AgentFormatting.firstLine(message)
                }
            }
            hub.announceFinished(id)

        default:
            break
        }
        return empty
    }

    /// Readable names for Antigravity's built-in tools.
    static func toolName(_ name: String) -> String {
        switch name {
        case "run_command": return "Command"
        case "view_file", "view_file_outline", "view_code_item": return "Read"
        case "write_to_file": return "Write"
        case "replace_file_content", "multi_replace_file_content": return "Edit"
        case "list_dir": return "List"
        case "find_by_name": return "Find"
        case "grep_search", "codebase_search": return "Search"
        case "search_web": return "Web search"
        case "read_url_content": return "Fetch"
        case "browser_subagent": return "Browser"
        case "call_mcp_tool": return "MCP"
        default: return name
        }
    }

    /// The tool's arguments with Antigravity's argument names mapped to the ones `AgentFormatting` looks for.
    static func toolInput(_ raw: Any?) -> [String: Any] {
        var args = raw as? [String: Any] ?? [:]
        if let text = raw as? String, let data = text.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            args = object
        }
        let aliases = [
            "command": ["CommandLine", "commandLine"],
            "path": ["TargetFile", "AbsolutePath", "File", "DirectoryPath", "SearchPath", "SearchDirectory"],
            "url": ["Url", "URL"],
            "query": ["Query"],
            "pattern": ["Pattern"],
        ]
        for (key, names) in aliases where args[key] == nil {
            if let value = names.compactMap({ args[$0] as? String }).first {
                args[key] = value
            }
        }
        return args
    }
}
