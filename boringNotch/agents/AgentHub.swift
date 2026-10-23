//
//  AgentHub.swift
//  boringNotch
//
//  Turns hook events from AI coding agents into sessions the notch can show, and holds the agent's hook open
//  while the user decides on a permission, plan or question in the notch.
//

import AppKit
import Defaults
import Foundation
import os

extension Notification.Name {
    /// An agent is waiting on the user. The notch opens on the Agents tab if the user allows it.
    static let agentNeedsAttention = Notification.Name("agentNeedsAttention")
    /// Every pending agent request has been dealt with.
    static let agentAttentionResolved = Notification.Name("agentAttentionResolved")
}

@MainActor
final class AgentHub: ObservableObject {
    static let shared = AgentHub()

    @Published private(set) var sessions: [String: AgentSession] = [:]
    @Published private(set) var requests: [AgentRequest] = []
    /// The session that most recently finished a turn, shown briefly in the closed notch.
    @Published private(set) var recentlyFinished: AgentSession?

    private let logger = Logger(subsystem: "com.theboringteam.boringnotch", category: "AgentHub")
    private var server: AgentBridgeServer?
    private var continuations: [UUID: CheckedContinuation<AgentDecision, Never>] = [:]
    private var recentlyFinishedTask: Task<Void, Never>?
    private var enabledObserver: Task<Void, Never>?

    /// Newest activity first.
    var orderedSessions: [AgentSession] {
        sessions.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    var activeSessions: [AgentSession] {
        orderedSessions.filter { $0.status.isActive }
    }

    func start() {
        guard enabledObserver == nil else { return }
        enabledObserver = Task { [weak self] in
            for await enabled in Defaults.updates(.agentIntegrationEnabled) {
                if enabled {
                    self?.startServer()
                } else {
                    self?.stopServer()
                }
            }
        }
    }

    private func startServer() {
        guard server == nil else { return }

        var token = Defaults[.agentBridgeToken]
        if token.isEmpty {
            token = UUID().uuidString + UUID().uuidString
            Defaults[.agentBridgeToken] = token
        }

        let bridgeToken = token
        let server = AgentBridgeServer(token: bridgeToken) { request, cancellation in
            await AgentHub.shared.handle(request, cancellation: cancellation)
        }
        server.onReady = { port in
            Task { @MainActor in
                await AgentIntegrationInstaller.shared.writeBridge(port: port, token: bridgeToken)
                await AgentIntegrationInstaller.shared.installDetectedAgents()
            }
        }
        do {
            try server.start()
            self.server = server
        } catch {
            logger.error("Couldn't start the agent bridge: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stopServer() {
        server?.stop()
        server = nil
        for id in continuations.keys {
            resolve(id, with: .handBack)
        }
        sessions.removeAll()
        recentlyFinished = nil
    }

    // MARK: - Decisions

    /// Answers a pending request from the notch.
    func resolve(_ requestID: UUID, with decision: AgentDecision) {
        guard let continuation = continuations.removeValue(forKey: requestID) else { return }
        requests.removeAll { $0.id == requestID }
        continuation.resume(returning: decision)
        if requests.isEmpty {
            NotificationCenter.default.post(name: .agentAttentionResolved, object: nil)
        }
    }

    func jump(to session: AgentSession) {
        TerminalJumper.jump(to: session.terminal)
    }

    private func awaitDecision(
        _ kind: AgentRequest.Kind,
        sessionID: String,
        agent: AgentKind,
        cancellation: AgentRequestCancellation
    ) async -> AgentDecision {
        let request = AgentRequest(sessionID: sessionID, agent: agent, kind: kind)
        return await withCheckedContinuation { continuation in
            continuations[request.id] = continuation
            requests.append(request)

            AgentSoundPlayer.shared.play(.attention)
            NotificationCenter.default.post(name: .agentNeedsAttention, object: nil)

            // The agent stopped waiting (interrupted, or its own hook timeout ran out)
            cancellation.onCancel { [weak self] in
                Task { @MainActor in self?.resolve(request.id, with: .handBack) }
            }

            // Give the decision back to the terminal if it's left unanswered for too long
            let timeout = Defaults[.agentDecisionTimeout]
            if timeout > 0 {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(timeout))
                    self?.resolve(request.id, with: .handBack)
                }
            }
        }
    }

    // MARK: - Events

    func handle(_ request: AgentHookRequest, cancellation: AgentRequestCancellation) async -> Data {
        guard Defaults[.agentIntegrationEnabled], let agent = AgentKind(rawValue: request.agent) else { return Data() }
        let payload = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
        removeStaleSessions()

        switch agent {
        case .claudeCode:
            return await handleClaudeCode(request.event, payload, terminal: request.terminal, cancellation: cancellation)
        case .codex:
            handleCodex(payload, terminal: request.terminal)
        case .geminiCLI:
            handleGemini(request.event, payload, terminal: request.terminal)
        }
        return Data()
    }

    // MARK: Claude Code

    private func handleClaudeCode(
        _ event: String,
        _ payload: [String: Any],
        terminal: TerminalLocation,
        cancellation: AgentRequestCancellation
    ) async -> Data {
        let id = "claude:" + (payload["session_id"] as? String ?? "default")
        let cwd = payload["cwd"] as? String ?? ""
        let tool = payload["tool_name"] as? String ?? ""
        let input = payload["tool_input"] as? [String: Any] ?? [:]

        func update(_ change: (inout AgentSession) -> Void) {
            updateSession(id: id, kind: .claudeCode, cwd: cwd, terminal: terminal, change)
        }

        switch event {
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
                    $0.activity = Self.activity(tool: tool, input: input)
                }
                return Data()
            }

            update {
                $0.status = .waitingForInput
                $0.activity = questions.first?.question
            }
            let decision = await awaitDecision(.questions(questions), sessionID: id, agent: .claudeCode, cancellation: cancellation)
            resumeWorking(id)

            guard case .answers(let answers) = decision else { return Data() }
            var answered = input
            answered["answers"] = answers
            let output: [String: Any] = [
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "updatedInput": answered,
            ]
            return Self.json(["hookSpecificOutput": output])

        case "PermissionRequest":
            let kind: AgentRequest.Kind = tool == "ExitPlanMode"
                ? .plan(markdown: input["plan"] as? String ?? "")
                : .permission(tool: tool, detail: Self.detail(tool: tool, input: input))
            update {
                $0.status = .waitingForApproval
                $0.activity = tool == "ExitPlanMode" ? "Plan ready for review" : Self.activity(tool: tool, input: input)
            }
            let decision = await awaitDecision(kind, sessionID: id, agent: .claudeCode, cancellation: cancellation)
            resumeWorking(id)

            var result: [String: Any]
            switch decision {
            case .allow:
                result = ["behavior": "allow"]
                // Plan approval needs the input passed back along with "allow"
                if tool == "ExitPlanMode" {
                    result["updatedInput"] = input
                }
            case .deny(let message):
                result = ["behavior": "deny"]
                if let message {
                    result["message"] = message
                }
            case .answers, .handBack:
                return Data()
            }
            let output: [String: Any] = [
                "hookEventName": "PermissionRequest",
                "decision": result,
            ]
            return Self.json(["hookSpecificOutput": output])

        case "Notification":
            // Claude is showing its own permission prompt in the terminal (e.g. after the notch handed it back)
            if payload["notification_type"] as? String == "permission_prompt",
               !requests.contains(where: { $0.sessionID == id }) {
                update {
                    $0.status = .waitingForApproval
                    $0.activity = payload["message"] as? String
                }
            }

        case "Stop":
            update {
                $0.status = .finished
                $0.activity = nil
                $0.lastMessage = (payload["last_assistant_message"] as? String).map(Self.firstLine)
            }
            announceFinished(id)

        case "SessionEnd":
            endSession(id)

        default:
            break
        }
        return Data()
    }

    // MARK: Codex

    private func handleCodex(_ payload: [String: Any], terminal: TerminalLocation) {
        // Codex's notify program is only told when a turn completes
        guard payload["type"] as? String == "agent-turn-complete" else { return }
        let id = "codex:" + (payload["thread-id"] as? String ?? payload["turn-id"] as? String ?? "default")
        updateSession(id: id, kind: .codex, cwd: payload["cwd"] as? String ?? "", terminal: terminal) {
            $0.status = .finished
            $0.activity = nil
            $0.lastMessage = (payload["last-assistant-message"] as? String).map(Self.firstLine)
        }
        announceFinished(id)
    }

    // MARK: Gemini CLI

    private func handleGemini(_ event: String, _ payload: [String: Any], terminal: TerminalLocation) {
        let id = "gemini:" + (payload["session_id"] as? String ?? "default")
        let cwd = payload["cwd"] as? String ?? ""

        func update(_ change: (inout AgentSession) -> Void) {
            updateSession(id: id, kind: .geminiCLI, cwd: cwd, terminal: terminal, change)
        }

        switch event {
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
                $0.activity = Self.activity(tool: payload["tool_name"] as? String ?? "", input: payload["tool_input"] as? [String: Any] ?? [:])
            }
        case "Notification":
            // Gemini asks for tool approval in the terminal; its hooks can't answer it, so point the user there
            if payload["notification_type"] as? String == "ToolPermission" {
                update {
                    $0.status = .waitingForApproval
                    $0.activity = payload["message"] as? String
                }
                AgentSoundPlayer.shared.play(.attention)
            }
        case "AfterAgent":
            update {
                $0.status = .finished
                $0.activity = nil
                $0.lastMessage = (payload["prompt_response"] as? String).map(Self.firstLine)
            }
            announceFinished(id)
        case "SessionEnd":
            endSession(id)
        default:
            break
        }
    }

    // MARK: - Sessions

    private func updateSession(
        id: String,
        kind: AgentKind,
        cwd: String,
        terminal: TerminalLocation,
        _ change: (inout AgentSession) -> Void
    ) {
        var session = sessions[id] ?? AgentSession(
            id: id,
            kind: kind,
            cwd: cwd,
            status: .idle,
            terminal: terminal,
            updatedAt: Date()
        )
        if !cwd.isEmpty {
            session.cwd = cwd
        }
        // Keep the richest location we've seen; some events come from processes without a terminal
        if terminal.tty != nil || terminal.appBundleID != nil {
            session.terminal = terminal
        }
        change(&session)
        session.updatedAt = Date()
        sessions[id] = session
    }

    private func resumeWorking(_ id: String) {
        guard var session = sessions[id], session.status.needsAttention else { return }
        session.status = .working
        session.activity = nil
        session.updatedAt = Date()
        sessions[id] = session
    }

    private func announceFinished(_ id: String) {
        guard let session = sessions[id] else { return }
        AgentSoundPlayer.shared.play(.done)

        recentlyFinishedTask?.cancel()
        recentlyFinished = session
        recentlyFinishedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.recentlyFinished = nil
        }
    }

    private func endSession(_ id: String) {
        for request in requests where request.sessionID == id {
            resolve(request.id, with: .handBack)
        }
        sessions.removeValue(forKey: id)
    }

    /// Drops sessions that went quiet long ago without ending (the terminal was closed, for example).
    private func removeStaleSessions() {
        let cutoff = Date().addingTimeInterval(-2 * 60 * 60)
        for (id, session) in sessions where session.updatedAt < cutoff && !requests.contains(where: { $0.sessionID == id }) {
            sessions.removeValue(forKey: id)
        }
    }

    // MARK: - Formatting

    private static func questions(from input: [String: Any]) -> [AgentQuestion]? {
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

    /// One line for the session list, e.g. "Bash: npm test" or "Edit: ContentView.swift".
    static func activity(tool: String, input: [String: Any]) -> String {
        guard !tool.isEmpty else { return "Working" }
        let target: String?
        if let path = input["file_path"] as? String ?? input["notebook_path"] as? String ?? input["absolute_path"] as? String {
            target = (path as NSString).lastPathComponent
        } else {
            target = input["command"] as? String
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
        if let path = input["file_path"] as? String ?? input["notebook_path"] as? String { return path }
        if let url = input["url"] as? String { return url }
        guard JSONSerialization.isValidJSONObject(input),
              let data = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return tool }
        return String(text.prefix(1000))
    }

    static func firstLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return String(line.prefix(200))
    }

    private static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])) ?? Data()
    }
}
