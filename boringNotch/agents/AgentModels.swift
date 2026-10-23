//
//  AgentModels.swift
//  boringNotch
//
//  AI coding agents (Claude Code, Codex, Gemini CLI, ...) report to the notch through their hook systems.
//  These are the shared types for their sessions and the decisions the notch makes for them.
//

import Foundation

enum AgentKind: String, CaseIterable, Identifiable, Codable {
    case claudeCode = "claude"
    case codex = "codex"
    case geminiCLI = "gemini"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .geminiCLI: return "Gemini CLI"
        }
    }

    var symbol: String {
        switch self {
        case .claudeCode: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .geminiCLI: return "diamond.fill"
        }
    }

    /// Whether the notch can approve tool calls and answer questions for this agent, rather than only
    /// showing what it's doing.
    var supportsDecisions: Bool {
        self == .claudeCode
    }
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
    var kittyWindow: String?
    var weztermPane: String?
}

struct AgentSession: Identifiable, Equatable {
    /// Agent kind and the agent's own session ID, so IDs from different agents never collide.
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
    case deny(message: String?)
    /// Answers keyed by question text. Multiple choices are joined with ", ".
    case answers([String: String])
    /// Hand the decision back to the agent's own prompt in the terminal.
    case handBack
}
