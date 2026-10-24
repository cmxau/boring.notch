//
//  OpenCodeIntegration.swift
//  boringNotch
//
//  OpenCode, through a small plugin of Boring Notch's own in ~/.config/opencode/plugin. The plugin forwards session
//  and tool events to the bridge script and never changes what OpenCode does. Status only: OpenCode's permission
//  prompts stay in OpenCode, and the notch shows when one is waiting.
//

import Foundation

struct OpenCodeIntegration: AgentIntegration {
    let kind = AgentKind(id: "opencode", displayName: "OpenCode", symbol: "terminal.fill", capabilities: [.status])

    private let pluginFile = ".config/opencode/plugin/boring-notch.js"

    var detectionPaths: [String] { [".config/opencode"] }
    var configFiles: [String] { [pluginFile] }

    func updatedConfigFiles(_ current: [String: Data], install: Bool, hookExecutable: String) throws -> [String: Data] {
        if let existing = current[pluginFile], !existing.isEmpty,
           !(String(data: existing, encoding: .utf8)?.contains(AgentHookCommand.marker) ?? false) {
            if install {
                throw AgentIntegrationError.conflictingSetting("\(pluginFile) wasn't written by Boring Notch, so it was left untouched.")
            }
            return [:]
        }
        let source = install ? Self.plugin(hookExecutable: hookExecutable) : Self.disabledPlugin
        return [pluginFile: Data(source.utf8)]
    }

    /// A JavaScript string literal.
    private static func jsString(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes])) ?? Data("[\"\"]".utf8)
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }

    private static let disabledPlugin = """
    // Boring Notch (boring-agent-hook) is disconnected from OpenCode. This plugin does nothing.
    export const BoringNotch = async () => ({})

    """

    private static func plugin(hookExecutable: String) -> String {
        """
        // Boring Notch: shows OpenCode sessions in the notch. Installed and kept up to date by Boring Notch
        // (boring-agent-hook); edits will be overwritten. It only reports events and never changes what OpenCode does.
        import { spawn } from "node:child_process"

        const script = \(jsString(hookExecutable))
        const reported = ["session.created", "session.idle", "session.error", "session.deleted", "permission.updated", "permission.asked"]

        function send(event, payload) {
          try {
            const child = spawn("/bin/sh", ["-c", 'test -x "$0" && "$0" opencode "$1"; exit 0', script, event], {
              stdio: ["pipe", "ignore", "ignore"],
              detached: true,
            })
            child.on("error", () => {})
            child.stdin.on("error", () => {})
            child.stdin.end(JSON.stringify(payload))
            child.unref()
          } catch {}
        }

        export const BoringNotch = async ({ directory }) => ({
          event: async ({ event }) => {
            if (!reported.includes(event.type)) return
            const properties = event.properties ?? {}
            const sessionID = properties.sessionID ?? properties.info?.id ?? null
            send(event.type, { sessionID, cwd: directory, properties })
          },
          "tool.execute.before": async (input, output) => {
            send("tool.execute.before", { sessionID: input.sessionID, cwd: directory, tool: input.tool, args: output?.args ?? {} })
          },
        })

        """
    }

    func handle(_ event: AgentEvent, hub: AgentHub) async -> Data {
        let id = event.sessionID(for: kind, event.string("sessionID"))
        let cwd = event.string("cwd") ?? ""

        func update(_ change: (inout AgentSession) -> Void) {
            hub.updateSession(id: id, kind: kind, cwd: cwd, terminal: event.terminal, change)
        }

        switch event.name {
        case "session.created":
            update { $0.status = .idle }
        case "tool.execute.before":
            let tool = event.string("tool") ?? ""
            update {
                $0.status = .working
                $0.activity = AgentFormatting.activity(tool: tool.capitalized, input: Self.normalized(event.object("args")))
            }
        case "permission.updated", "permission.asked":
            let title = event.object("properties")["title"] as? String
            update {
                $0.status = .waitingForApproval
                $0.activity = title ?? "Waiting for permission"
            }
            hub.alert(.attention)
        case "session.idle":
            update {
                $0.status = .finished
                $0.activity = nil
            }
            hub.announceFinished(id)
        case "session.error":
            update {
                $0.status = .finished
                $0.activity = nil
                $0.lastMessage = "Stopped with an error"
            }
            hub.alert(.error)
        case "session.deleted":
            hub.endSession(id)
        default:
            break
        }
        return Data()
    }

    /// OpenCode names arguments in camelCase (filePath); `AgentFormatting` looks for snake_case.
    private static func normalized(_ args: [String: Any]) -> [String: Any] {
        var args = args
        if args["file_path"] == nil, let path = args["filePath"] as? String {
            args["file_path"] = path
        }
        return args
    }
}
