//
//  CopilotCLIIntegration.swift
//  boringNotch
//
//  GitHub Copilot CLI, through a hooks file of Boring Notch's own in ~/.copilot/hooks. Status only: Copilot's
//  approvals stay in the terminal.
//

import Foundation

struct CopilotCLIIntegration: AgentIntegration {
    let kind = AgentKind(id: "copilot", displayName: "Copilot CLI", symbol: "airplane", capabilities: [.status])

    private let hooksFile = ".copilot/hooks/boring-notch.json"
    private let events = ["sessionStart", "userPromptSubmitted", "postToolUse", "agentStop", "sessionEnd"]

    var detectionPaths: [String] { [".copilot"] }
    var configFiles: [String] { [hooksFile] }

    func updatedConfigFiles(_ current: [String: Data], install: Bool, hookExecutable: String) throws -> [String: Data] {
        let existing = try JSONHookSettings.parseObject(current[hooksFile], file: hooksFile)
        let isOwn = existing.isEmpty || (String(data: current[hooksFile] ?? Data(), encoding: .utf8)?.contains(AgentHookCommand.marker) ?? false)
        guard isOwn else {
            if install {
                throw AgentIntegrationError.conflictingSetting("\(hooksFile) wasn't written by Boring Notch, so it was left untouched.")
            }
            return [:]
        }

        var hooks: [String: Any] = [:]
        if install {
            for event in events {
                hooks[event] = [[
                    "type": "command",
                    "bash": AgentHookCommand.shell(agent: kind.id, event: event, executable: hookExecutable),
                    "timeoutSec": 10,
                ] as [String: Any]]
            }
        }
        // The file is Boring Notch's alone; disconnecting leaves it with no hooks
        return [hooksFile: try JSONHookSettings.serialize(["version": 1, "hooks": hooks])]
    }

    func handle(_ event: AgentEvent, hub: AgentHub) async -> Data {
        let id = event.sessionID(for: kind, event.string("sessionId") ?? event.string("session_id"))
        let cwd = event.string("cwd") ?? ""

        func update(_ change: (inout AgentSession) -> Void) {
            hub.updateSession(id: id, kind: kind, cwd: cwd, terminal: event.terminal, change)
        }

        switch event.name {
        case "sessionStart":
            update { $0.status = .idle }
        case "userPromptSubmitted":
            update {
                $0.status = .working
                $0.activity = nil
            }
        case "postToolUse":
            let tool = event.string("toolName") ?? event.string("tool_name") ?? ""
            var input = event.object("toolArgs")
            if input.isEmpty, let text = event.string("toolArgs"), let data = text.data(using: .utf8) {
                input = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            }
            update {
                $0.status = .working
                $0.activity = AgentFormatting.activity(tool: tool, input: input)
            }
        case "agentStop":
            update {
                $0.status = .finished
                $0.activity = nil
            }
            hub.announceFinished(id)
        case "sessionEnd":
            hub.endSession(id)
        default:
            break
        }
        return Data()
    }
}
