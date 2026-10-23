//
//  AgentsView.swift
//  boringNotch
//
//  The Agents tab: every running AI agent at a glance, and whatever they're waiting on you for.
//

import SwiftUI

struct AgentsView: View {
    @ObservedObject var hub = AgentHub.shared

    var body: some View {
        if hub.sessions.isEmpty && hub.requests.isEmpty {
            EmptyStateView(message: "No agents running. Start Claude Code, Codex or Gemini CLI in a terminal.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 12) {
                AgentSessionList(sessions: hub.orderedSessions, highlighted: hub.requests.first?.sessionID)
                    .frame(width: 210)

                Group {
                    if let request = hub.requests.first {
                        AgentRequestCard(
                            request: request,
                            session: hub.sessions[request.sessionID],
                            pendingCount: hub.requests.count
                        )
                        .id(request.id)
                    } else if let session = hub.orderedSessions.first {
                        AgentSessionSummary(session: session)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Session list

private struct AgentSessionList: View {
    let sessions: [AgentSession]
    let highlighted: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                ForEach(sessions) { session in
                    Button {
                        AgentHub.shared.jump(to: session)
                    } label: {
                        AgentSessionRow(session: session, isHighlighted: session.id == highlighted)
                    }
                    .buttonStyle(.plain)
                    .help("Jump to \(session.projectName)")
                }
            }
        }
    }
}

private struct AgentSessionRow: View {
    let session: AgentSession
    let isHighlighted: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            AgentStatusIcon(kind: session.kind, status: session.status, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.projectName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(session.activity ?? session.status.label)
                    .font(.system(size: 10))
                    .foregroundStyle(session.status.tint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isHighlighted ? 0.12 : (isHovering ? 0.08 : 0.04)))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

private struct AgentSessionSummary: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AgentCardHeader(session: session, agent: session.kind, pendingCount: 0)
            Text(session.lastMessage ?? session.activity ?? session.status.label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(4)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                AgentButton("Jump to terminal", systemImage: "arrow.up.forward.app", role: .secondary) {
                    AgentHub.shared.jump(to: session)
                }
            }
        }
    }
}

// MARK: - Requests

private struct AgentRequestCard: View {
    let request: AgentRequest
    let session: AgentSession?
    let pendingCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AgentCardHeader(session: session, agent: request.agent, pendingCount: pendingCount)

            switch request.kind {
            case .permission(let tool, let detail):
                PermissionRequestView(request: request, session: session, tool: tool, detail: detail)
            case .plan(let markdown):
                PlanReviewView(request: request, session: session, markdown: markdown)
            case .questions(let questions):
                QuestionsView(request: request, session: session, questions: questions)
            }
        }
    }
}

private struct AgentCardHeader: View {
    let session: AgentSession?
    let agent: AgentKind
    let pendingCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: agent.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
            Text(agent.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
            if let session {
                Text("·  \(session.projectName)")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if pendingCount > 1 {
                Text("+\(pendingCount - 1) waiting")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
            }
        }
    }
}

private struct PermissionRequestView: View {
    let request: AgentRequest
    let session: AgentSession?
    let tool: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            ScrollView(.vertical, showsIndicators: false) {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
            HStack(spacing: 6) {
                TerminalButton(request: request, session: session)
                Spacer()
                AgentButton("Deny", systemImage: "xmark", role: .destructive) {
                    AgentHub.shared.resolve(request.id, with: .deny(message: nil))
                }
                AgentButton("Allow", systemImage: "checkmark", role: .primary) {
                    AgentHub.shared.resolve(request.id, with: .allow)
                }
            }
        }
    }

    private var title: String {
        switch tool {
        case "Bash": return "Run this command?"
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return "Allow \(tool) on this file?"
        case "WebFetch": return "Fetch this page?"
        default: return "Allow \(tool)?"
        }
    }
}

private struct PlanReviewView: View {
    let request: AgentRequest
    let session: AgentSession?
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Plan ready for review")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            ScrollView(.vertical, showsIndicators: true) {
                Text(rendered)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
            HStack(spacing: 6) {
                TerminalButton(request: request, session: session)
                Spacer()
                AgentButton("Keep planning", systemImage: "arrow.uturn.backward", role: .secondary) {
                    AgentHub.shared.resolve(
                        request.id,
                        with: .deny(message: "The user wants to keep planning. Revise the plan before starting work.")
                    )
                }
                AgentButton("Approve plan", systemImage: "checkmark", role: .primary) {
                    AgentHub.shared.resolve(request.id, with: .allow)
                }
            }
        }
    }

    private var rendered: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }
}

private struct QuestionsView: View {
    let request: AgentRequest
    let session: AgentSession?
    let questions: [AgentQuestion]

    @State private var index = 0
    @State private var answers: [String: String] = [:]
    @State private var selection: Set<String> = []

    var body: some View {
        let question = questions[min(index, questions.count - 1)]
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(question.question)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if questions.count > 1 {
                    Text("\(index + 1) of \(questions.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                }
            }
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(question.options, id: \.self) { option in
                        OptionButton(
                            option: option,
                            isSelected: selection.contains(option.label),
                            showsCheckbox: question.multiSelect
                        ) {
                            choose(option, in: question)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                TerminalButton(request: request, session: session)
                Spacer()
                if question.multiSelect {
                    AgentButton(index == questions.count - 1 ? "Submit" : "Next", systemImage: "checkmark", role: .primary) {
                        record(selection.sorted().joined(separator: ", "), for: question)
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
    }

    private func choose(_ option: AgentQuestion.Option, in question: AgentQuestion) {
        if question.multiSelect {
            if selection.contains(option.label) {
                selection.remove(option.label)
            } else {
                selection.insert(option.label)
            }
        } else {
            record(option.label, for: question)
        }
    }

    private func record(_ answer: String, for question: AgentQuestion) {
        answers[question.question] = answer
        selection = []
        if index < questions.count - 1 {
            withAnimation(.smooth) { index += 1 }
        } else {
            AgentHub.shared.resolve(request.id, with: .answers(answers))
        }
    }
}

private struct OptionButton: View {
    let option: AgentQuestion.Option
    let isSelected: Bool
    let showsCheckbox: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 6) {
                if showsCheckbox {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? .orange : .gray)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 10))
                            .foregroundStyle(.gray)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.16 : (isHovering ? 0.1 : 0.06)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// Gives the decision back to the agent's own prompt and brings its terminal forward.
private struct TerminalButton: View {
    let request: AgentRequest
    let session: AgentSession?

    var body: some View {
        AgentButton("Terminal", systemImage: "terminal", role: .secondary) {
            AgentHub.shared.resolve(request.id, with: .handBack)
            if let session {
                AgentHub.shared.jump(to: session)
            }
        }
        .help("Answer in the terminal instead")
    }
}

// MARK: - Shared pieces

struct AgentButton: View {
    enum Role {
        case primary
        case secondary
        case destructive
    }

    let title: String
    let systemImage: String
    let role: Role
    let action: () -> Void
    @State private var isHovering = false

    init(_ title: String, systemImage: String, role: Role, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(background.opacity(isHovering ? 1 : 0.85)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var foreground: Color {
        role == .primary ? .black : .white
    }

    private var background: Color {
        switch role {
        case .primary: return .white
        case .secondary: return Color.white.opacity(0.14)
        case .destructive: return Color.red.opacity(0.35)
        }
    }
}

/// The agent's icon with its state: a spinning ring while it works, a dot when it needs you, a tick when done.
struct AgentStatusIcon: View {
    let kind: AgentKind
    let status: AgentStatus
    let size: CGFloat

    @State private var spinning = false

    var body: some View {
        ZStack {
            Image(systemName: kind.symbol)
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.5, height: size * 0.5)
                .foregroundStyle(.white)

            switch status {
            case .working:
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: max(1.5, size * 0.09), lineCap: .round))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            spinning = true
                        }
                    }
                    .onDisappear { spinning = false }
            case .waitingForApproval, .waitingForInput:
                Circle()
                    .stroke(Color.orange, lineWidth: max(1.5, size * 0.09))
                Circle()
                    .fill(Color.orange)
                    .frame(width: size * 0.3, height: size * 0.3)
                    .offset(x: size * 0.36, y: -size * 0.36)
            case .finished:
                Circle()
                    .stroke(Color.green.opacity(0.8), lineWidth: max(1.5, size * 0.09))
            case .idle:
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: max(1.5, size * 0.09))
            }
        }
        .frame(width: size, height: size)
    }
}

extension AgentStatus {
    var label: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .waitingForApproval: return "Needs approval"
        case .waitingForInput: return "Needs your input"
        case .finished: return "Done"
        }
    }

    var tint: Color {
        switch self {
        case .idle: return .gray
        case .working: return .white.opacity(0.7)
        case .waitingForApproval, .waitingForInput: return .orange
        case .finished: return .green
        }
    }
}
