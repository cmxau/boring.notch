//
//  ClaudeStyleIntegration.swift
//  boringNotch
//
//  Claude Code, and agents that copied its hook system (same events, payloads and decision output).
//  Permissions are answered through PermissionRequest, questions through PreToolUse on AskUserQuestion, and
//  plans through PermissionRequest on ExitPlanMode.
//

import Foundation

struct ClaudeStyleIntegration: AgentIntegration {
    let kind: AgentKind
    /// Home-relative folder that exists when the agent is installed, e.g. ".claude".
    let configFolder: String
    /// Home-relative settings file holding the hooks, e.g. ".claude/settings.json".
    let settingsFile: String

    static let claudeCode = ClaudeStyleIntegration(
        kind: AgentKind(
            id: "claude",
            displayName: "Claude Code",
            symbol: "sparkle",
            capabilities: [.status, .approvals, .questions, .plans]
        ),
        configFolder: ".claude",
        settingsFile: ".claude/settings.json"
    )

    var detectionPaths: [String] { [configFolder] }
    var configFiles: [String] { [settingsFile] }

    private var events: [JSONHookSettings.Event] {
        [
            .init("SessionStart", timeout: 10),
            .init("SessionEnd", timeout: 5),
            .init("UserPromptSubmit", timeout: 10),
            // Questions wait in the notch; every other tool call returns within a few seconds
            .init("PreToolUse", matcher: "*", timeout: 86400, wait: .forTools(["AskUserQuestion"])),
            .init("PermissionRequest", matcher: "*", timeout: 86400, wait: .always),
            .init("Notification", matcher: "*", timeout: 10),
            .init("Stop", timeout: 10),
        ]
    }

    func updatedConfigFiles(_ current: [String: Data], install: Bool, hookExecutable: String) throws -> [String: Data] {
        let updated = try JSONHookSettings.updated(
            current[settingsFile],
            file: settingsFile,
            agent: kind.id,
            events: events,
            install: install,
            hookExecutable: hookExecutable
        )
        return [settingsFile: updated]
    }

    func handle(_ event: AgentEvent, hub: AgentHub) async -> Data {
        let id = event.sessionID(for: kind, event.string("session_id"))
        let cwd = event.string("cwd") ?? ""
        let tool = event.string("tool_name") ?? ""
        let input = event.object("tool_input")

        func update(_ change: (inout AgentSession) -> Void) {
            hub.updateSession(id: id, kind: kind, cwd: cwd, terminal: event.terminal, change)
        }

        switch event.name {
        case "SessionStart":
            update { $0.status = .idle }

        case "UserPromptSubmit":
            update {
                $0.status = .working
                $0.activity = nil
            }

        case "PreToolUse":
            guard tool == "AskUserQuestion", let questions = Self.questions(from: input) else {
                update {
                    $0.status = .working
                    $0.activity = AgentFormatting.activity(tool: tool, input: input)
                }
                return Data()
            }

            update {
                $0.status = .waitingForInput
                $0.activity = questions.first?.question
            }
            let decision = await hub.awaitDecision(.questions(questions), sessionID: id, agent: kind, cancellation: event.cancellation)
            hub.resumeWorking(id)

            guard case .answers(let answers) = decision else { return Data() }
            var answered = input
            answered["answers"] = answers
            let output: [String: Any] = [
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "updatedInput": answered,
            ]
            return AgentFormatting.json(["hookSpecificOutput": output])

        case "PermissionRequest":
            let isPlan = tool == "ExitPlanMode"
            let request: AgentRequest.Kind = isPlan
                ? .plan(markdown: input["plan"] as? String ?? "")
                : .permission(tool: tool, detail: AgentFormatting.detail(tool: tool, input: input))
            update {
                $0.status = .waitingForApproval
                $0.activity = isPlan ? "Plan ready for review" : AgentFormatting.activity(tool: tool, input: input)
            }
            let decision = await hub.awaitDecision(request, sessionID: id, agent: kind, cancellation: event.cancellation)
            hub.resumeWorking(id)

            var result: [String: Any]
            switch decision {
            case .allow:
                result = ["behavior": "allow"]
                // Plan approval needs the input passed back along with "allow"
                if isPlan {
                    result["updatedInput"] = input
                }
            case .deny(let message):
                result = ["behavior": "deny"]
                if let message, !message.isEmpty {
                    result["message"] = message
                }
            case .answers, .handBack:
                return Data()
            }
            let output: [String: Any] = [
                "hookEventName": "PermissionRequest",
                "decision": result,
            ]
            return AgentFormatting.json(["hookSpecificOutput": output])

        case "Notification":
            // The agent is showing its own permission prompt in the terminal (e.g. after the notch handed it back)
            if event.string("notification_type") == "permission_prompt", !hub.hasPendingRequest(for: id) {
                update {
                    $0.status = .waitingForApproval
                    $0.activity = event.string("message")
                }
            }

        case "Stop":
            update {
                $0.status = .finished
                $0.activity = nil
                $0.lastMessage = event.string("last_assistant_message").map(AgentFormatting.firstLine)
            }
            hub.announceFinished(id)

        case "SessionEnd":
            hub.endSession(id)

        default:
            break
        }
        return Data()
    }

    static func questions(from input: [String: Any]) -> [AgentQuestion]? {
        guard let raw = input["questions"] as? [[String: Any]], !raw.isEmpty else { return nil }
        let questions = raw.compactMap { item -> AgentQuestion? in
            guard let question = item["question"] as? String else { return nil }
            let options = (item["options"] as? [[String: Any]] ?? []).compactMap { option -> AgentQuestion.Option? in
                guard let label = option["label"] as? String else { return nil }
                return AgentQuestion.Option(label: label, description: option["description"] as? String)
            }
            return AgentQuestion(
                question: question,
                header: item["header"] as? String,
                options: options,
                multiSelect: item["multiSelect"] as? Bool ?? false
            )
        }
        return questions.isEmpty ? nil : questions
    }
}
