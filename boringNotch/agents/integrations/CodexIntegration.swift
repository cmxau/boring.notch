//
//  CodexIntegration.swift
//  boringNotch
//
//  OpenAI Codex CLI. Codex runs a `notify` program from ~/.codex/config.toml when a turn completes, passing the
//  event JSON as its last argument.
//

import Foundation

struct CodexIntegration: AgentIntegration {
    let kind = AgentKind(
        id: "codex",
        displayName: "Codex",
        symbol: "chevron.left.forwardslash.chevron.right",
        capabilities: [.status]
    )

    private let configFile = ".codex/config.toml"

    var detectionPaths: [String] { [".codex"] }
    var configFiles: [String] { [configFile] }

    func updatedConfigFiles(_ current: [String: Data], install: Bool, hookExecutable: String) throws -> [String: Data] {
        let text = current[configFile].flatMap { String(data: $0, encoding: .utf8) } ?? ""
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")

        // Top-level keys come before the first [table] header
        let firstTable = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.endIndex
        let notifyIndex = lines[..<firstTable].firstIndex {
            $0.trimmingCharacters(in: .whitespaces).range(of: #"^notify\s*="#, options: .regularExpression) != nil
        }

        if let notifyIndex {
            guard lines[notifyIndex].contains(AgentHookCommand.marker) else {
                // Someone else's notify program; Codex only allows one
                if install {
                    throw AgentIntegrationError.conflictingSetting("Codex already runs another notify program, so it was left untouched.")
                }
                return [:]
            }
            lines.remove(at: notifyIndex)
        }

        if install {
            let arguments = AgentHookCommand.argv(agent: kind.id, event: "turn-complete", executable: hookExecutable)
            lines.insert("notify = [" + arguments.map(TOML.string).joined(separator: ", ") + "]", at: 0)
        }

        var result = lines.joined(separator: "\n")
        if !result.isEmpty && !result.hasSuffix("\n") {
            result += "\n"
        }
        return [configFile: Data(result.utf8)]
    }

    func handle(_ event: AgentEvent, hub: AgentHub) async -> Data {
        // The notify program is only told when a turn completes
        guard event.string("type") == "agent-turn-complete" else { return Data() }
        let id = event.sessionID(for: kind, event.string("thread-id") ?? event.string("turn-id"))
        hub.updateSession(id: id, kind: kind, cwd: event.string("cwd") ?? "", terminal: event.terminal) {
            $0.status = .finished
            $0.activity = nil
            $0.lastMessage = event.string("last-assistant-message").map(AgentFormatting.firstLine)
        }
        hub.announceFinished(id)
        return Data()
    }
}

enum TOML {
    /// A TOML basic string.
    static func string(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
