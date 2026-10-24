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

    /// For the approve and deny shortcuts. Questions need an answer picked, so they're left alone.
    func answerFirstRequest(approve: Bool) {
        guard let request = requests.first else { return }
        if case .questions = request.kind { return }
        resolve(request.id, with: approve ? .allow : .deny(message: nil))
    }

    /// For the jump-to-terminal shortcut: the session that's waiting, or the most recent one.
    func jumpToWaitingSession() {
        if let request = requests.first, let session = sessions[request.sessionID] {
            jump(to: session)
        } else if let session = orderedSessions.first {
            jump(to: session)
        }
    }

    func jump(to session: AgentSession) {
        TerminalJumper.jump(to: session.terminal)
    }

    // MARK: - For integrations

    /// Shows a request in the notch and waits for the user's decision. Returns `.handBack` if the agent stops
    /// waiting, or nobody answers before the hand-back timeout.
    func awaitDecision(
        _ kind: AgentRequest.Kind,
        sessionID: String,
        agent: AgentKind,
        cancellation: AgentRequestCancellation
    ) async -> AgentDecision {
        let request = AgentRequest(sessionID: sessionID, agent: agent, kind: kind)
        return await withCheckedContinuation { continuation in
            continuations[request.id] = continuation
            requests.append(request)

            if case .questions = kind {
                alert(.question)
            } else {
                alert(.attention)
            }
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

    /// Creates or updates a session. Pass the agent's working folder and the event's terminal location;
    /// empty values don't overwrite what's already known.
    func updateSession(
        id: String,
        kind: AgentKind,
        cwd: String,
        terminal: TerminalLocation,
        _ change: (inout AgentSession) -> Void
    ) {
        let isNew = sessions[id] == nil
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
        if terminal.tty != nil || terminal.appBundleID != nil || terminal.tmuxPane != nil {
            session.terminal = terminal
        }
        change(&session)
        session.updatedAt = Date()
        sessions[id] = session
        if isNew {
            alert(.sessionStarted)
        }
    }

    /// Back to "working" after the user answers a request.
    func resumeWorking(_ id: String) {
        guard var session = sessions[id], session.status.needsAttention else { return }
        session.status = .working
        session.activity = nil
        session.updatedAt = Date()
        sessions[id] = session
    }

    /// The agent finished its turn: play the "done" sound and show it briefly in the closed notch.
    func announceFinished(_ id: String) {
        guard let session = sessions[id] else { return }
        alert(.done)

        recentlyFinishedTask?.cancel()
        recentlyFinished = session
        recentlyFinishedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.recentlyFinished = nil
        }
    }

    func endSession(_ id: String) {
        for request in requests where request.sessionID == id {
            resolve(request.id, with: .handBack)
        }
        sessions.removeValue(forKey: id)
    }

    func hasPendingRequest(for sessionID: String) -> Bool {
        requests.contains { $0.sessionID == sessionID }
    }

    func alert(_ cue: AgentSoundCue) {
        AgentSoundPlayer.shared.play(cue)
    }

    // MARK: - Events

    func handle(_ request: AgentHookRequest, cancellation: AgentRequestCancellation) async -> Data {
        guard Defaults[.agentIntegrationEnabled], let integration = AgentRegistry.integration(id: request.agent) else {
            return Data()
        }
        removeStaleSessions()
        let event = AgentEvent(
            name: request.event,
            payload: (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:],
            rawBody: request.body,
            terminal: request.terminal,
            cancellation: cancellation
        )
        return await integration.handle(event, hub: self)
    }

    /// Drops sessions that went quiet long ago without ending (the terminal was closed, for example).
    private func removeStaleSessions() {
        let cutoff = Date().addingTimeInterval(-2 * 60 * 60)
        for (id, session) in sessions where session.updatedAt < cutoff && !hasPendingRequest(for: id) {
            sessions.removeValue(forKey: id)
        }
    }
}
