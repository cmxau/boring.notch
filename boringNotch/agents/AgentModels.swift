//
//  AgentModels.swift
//  boringNotch
//
//  AI coding agents (Claude Code, Codex, Gemini CLI, ...) report to the notch through their hook systems.
//  These are the shared types for their sessions and the decisions the notch makes for them.
//

import Foundation

/// An AI agent the notch knows about. Each one is described by an `AgentIntegration` in `AgentRegistry`.
struct AgentKind: Hashable, Identifiable {
    struct Capabilities: OptionSet, Hashable {
        let rawValue: Int

        /// Working / needs you / done.
        static let status = Capabilities(rawValue: 1 << 0)
        /// Allow or deny tool calls from the notch.
        static let approvals = Capabilities(rawValue: 1 << 1)
        /// Answer the agent's multiple-choice questions from the notch.
        static let questions = Capabilities(rawValue: 1 << 2)
        /// Review and approve plans from the notch.
        static let plans = Capabilities(rawValue: 1 << 3)
    }

    /// Stable identifier, also the agent's path in the bridge URL (`/v1/hooks/<id>`), e.g. "claude".
    let id: String
    let displayName: String
    /// SF Symbol shown for the agent.
    let symbol: String
    let capabilities: Capabilities

    var supportsDecisions: Bool {
        !capabilities.isDisjoint(with: [.approvals, .questions, .plans])
    }

    static func == (lhs: AgentKind, rhs: AgentKind) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum AgentStatus: Equatable {
    case idle
    case working
    case waitingForApproval
    case waitingForInput
    case finished

    var needsAttention: Bool {
        self == .waitingForApproval || self == .waitingForInput
    }

    var isActive: Bool {
        self == .working || needsAttention
    }
}

/// Where an agent is running, so the notch can bring that terminal, tab or pane back to the front.
struct TerminalLocation: Equatable {
    var tty: String?
    /// `TERM_PROGRAM`, e.g. "Apple_Terminal", "iTerm.app", "ghostty", "vscode".
    var program: String?
    /// Bundle identifier of the app hosting the terminal (macOS sets `__CFBundleIdentifier` for its children).
    var appBundleID: String?
    /// iTerm2 or Terminal.app session identifier.
    var sessionID: String?
    var tmuxPane: String?
    /// tmux server socket (`$TMUX`), needed to address the right tmux server.
    var tmuxSocket: String?
    var kittyWindow: String?
    /// kitty remote control socket (`$KITTY_LISTEN_ON`).
    var kittySocket: String?
    var weztermPane: String?
    /// The agent's process ID.
    var pid: Int32?
    /// Host name for agents running on a remote server over SSH; nil when they run on this Mac.
    var remoteHost: String?
}

struct AgentSession: Identifiable, Equatable {
    /// Agent ID, host (for remote agents) and the agent's own session ID, so IDs never collide.
    let id: String
    let kind: AgentKind
    var cwd: String
    var status: AgentStatus
    /// Short description of what the agent is doing right now, e.g. "Bash: npm test".
    var activity: String?
    var lastMessage: String?
    var terminal: TerminalLocation
    var updatedAt: Date

    var projectName: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? kind.displayName : name
    }

    var remoteHost: String? { terminal.remoteHost }
}

struct AgentQuestion: Equatable {
    struct Option: Equatable, Hashable {
        let label: String
        let description: String?
    }

    let question: String
    let header: String?
    let options: [Option]
    let multiSelect: Bool
}

/// Something an agent is waiting on the user for.
struct AgentRequest: Identifiable, Equatable {
    enum Kind: Equatable {
        /// A tool call that needs permission. `detail` is the command, file path or other input worth showing.
        case permission(tool: String, detail: String)
        /// The agent's plan, as Markdown, waiting to be approved before it starts work.
        case plan(markdown: String)
        case questions([AgentQuestion])
    }

    let id = UUID()
    let sessionID: String
    let agent: AgentKind
    let kind: Kind
    let createdAt = Date()
}

enum AgentDecision: Equatable {
    case allow
    /// Deny, optionally with a message for the agent (for plans, the user's feedback).
    case deny(message: String?)
    /// Answers keyed by question text. Multiple choices are joined with ", ".
    case answers([String: String])
    /// Hand the decision back to the agent's own prompt in the terminal.
    case handBack
}
