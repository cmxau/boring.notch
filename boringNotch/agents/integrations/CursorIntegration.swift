//
//  CursorIntegration.swift
//  boringNotch
//
//  Cursor (the editor and its CLI agent), through the user-wide hooks in ~/.cursor/hooks.json. Only hooks that
//  can't change what the agent does are used, so Cursor's own approvals keep working as they are: the notch shows
//  the prompt being worked on, commands and edits as they happen, and when the agent stops.
//

import Foundation

struct CursorIntegration: AgentIntegration {
    let kind = AgentKind(id: "cursor", displayName: "Cursor", symbol: "cursorarrow.rays", capabilities: [.status])

    private let hooksFile = ".cursor/hooks.json"
    private let events = ["beforeSubmitPrompt", "afterShellExecution", "afterFileEdit", "stop"]

    var detectionPaths: [String] { [".cursor"] }
    var configFiles: [String] { [hooksFile] }

    func updatedConfigFiles(_ current: [String: Data], install: Bool, hookExecutable: String) throws -> [String: Data] {
        var root = try JSONHookSettings.parseObject(current[hooksFile], file: hooksFile)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var entries = (hooks[event] as? [[String: Any]] ?? []).filter { !JSONHookSettings.isOwn($0) }
            if install {
                entries.append(["command": AgentHookCommand.shell(agent: kind.id, event: event, executable: hookExecutable)])
            }
            hooks[event] = entries.isEmpty ? nil : entries
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        if root["version"] == nil, !hooks.isEmpty {
            root["version"] = 1
        }
        return [hooksFile: try JSONHookSettings.serialize(root)]
    }

    func handle(_ event: AgentEvent, hub: AgentHub) async -> Data {
        let id = event.sessionID(for: kind, event.string("conversation_id"))
        let cwd = (event.payload["workspace_roots"] as? [String])?.first ?? ""

        func update(_ change: (inout AgentSession) -> Void) {
            hub.updateSession(id: id, kind: kind, cwd: cwd, terminal: event.terminal, change)
        }

        switch event.name {
        case "beforeSubmitPrompt":
            update {
                $0.status = .working
                $0.activity = nil
            }
            // The prompt goes ahead unchanged
            return AgentFormatting.json(["continue": true])
        case "afterShellExecution":
            update {
                $0.status = .working
                $0.activity = AgentFormatting.activity(tool: "Command", input: ["command": event.string("command") ?? ""])
            }
        case "afterFileEdit":
            update {
                $0.status = .working
                $0.activity = AgentFormatting.activity(tool: "Edit", input: ["file_path": event.string("file_path") ?? ""])
            }
        case "stop":
            update {
                $0.status = .finished
                $0.activity = nil
            }
            hub.announceFinished(id)
        default:
            break
        }
        return Data()
    }
}
