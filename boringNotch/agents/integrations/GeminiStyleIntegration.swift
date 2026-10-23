//
//  GeminiStyleIntegration.swift
//  boringNotch
//
//  Gemini CLI, and agents built on it that kept its hook system. Its hooks can't answer the CLI's own tool
//  approval prompt, so the notch reports status and points the user to the terminal when approval is needed.
//

import Foundation

struct GeminiStyleIntegration: AgentIntegration {
    let kind: AgentKind
    let configFolder: String
    let settingsFile: String

    static let geminiCLI = GeminiStyleIntegration(
        kind: AgentKind(id: "gemini", displayName: "Gemini CLI", symbol: "diamond.fill", capabilities: [.status]),
        configFolder: ".gemini",
        settingsFile: ".gemini/settings.json"
    )

    var detectionPaths: [String] { [configFolder] }
    var configFiles: [String] { [settingsFile] }

    private var events: [JSONHookSettings.Event] {
        // Timeouts are in milliseconds
        [
            .init("SessionStart", timeout: 5000),
            .init("SessionEnd", timeout: 5000),
            .init("BeforeAgent", timeout: 5000),
            .init("BeforeTool", matcher: "*", timeout: 5000),
            .init("AfterTool", matcher: "*", timeout: 5000),
            .init("Notification", timeout: 5000),
            .init("AfterAgent", timeout: 5000),
        ]
    }

    func updatedConfigFiles(_ current: [String: Data], install: Bool, hookExecutable: String) throws -> [String: Data] {
        let updated = try JSONHookSettings.updated(
            current[settingsFile],
            file: settingsFile,
            agent: kind.id,
            events: events,
            install: install,
            hookExecutable: hookExecutable,
            extraFields: ["name": "boring-notch"]
        )
        return [settingsFile: updated]
    }

    func handle(_ event: AgentEvent, hub: AgentHub) async -> Data {
        let id = event.sessionID(for: kind, event.string("session_id"))
        let cwd = event.string("cwd") ?? ""

        func update(_ change: (inout AgentSession) -> Void) {
            hub.updateSession(id: id, kind: kind, cwd: cwd, terminal: event.terminal, change)
        }

        switch event.name {
        case "SessionStart":
            update { $0.status = .idle }
        case "BeforeAgent":
            update {
                $0.status = .working
                $0.activity = nil
            }
        case "BeforeTool", "AfterTool":
            update {
                $0.status = .working
                $0.activity = AgentFormatting.activity(tool: event.string("tool_name") ?? "", input: event.object("tool_input"))
            }
        case "Notification":
            // Tool approval happens in the terminal; point the user there
            if event.string("notification_type") == "ToolPermission" {
                update {
                    $0.status = .waitingForApproval
                    $0.activity = event.string("message")
                }
                hub.alert(.attention)
            }
        case "AfterAgent":
            update {
                $0.status = .finished
                $0.activity = nil
                $0.lastMessage = event.string("prompt_response").map(AgentFormatting.firstLine)
            }
            hub.announceFinished(id)
        case "SessionEnd":
            hub.endSession(id)
        default:
            break
        }
        return Data()
    }
}
