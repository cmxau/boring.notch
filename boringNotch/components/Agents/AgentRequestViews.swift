//
//  AgentRequestViews.swift
//  boringNotch
//
//  What an agent is waiting on you for: a permission, a plan to review, or questions to answer.
//

import SwiftUI

// MARK: - Requests

struct AgentRequestCard: View {
    let request: AgentRequest
    let session: AgentSession?
    let pendingCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AgentCardHeader(session: session, agent: request.agent, pendingCount: pendingCount)

            switch request.kind {
            case .permission(let tool, let detail):
                AgentPermissionView(request: request, session: session, tool: tool, detail: detail)
            case .plan(let markdown):
                PlanReviewView(request: request, session: session, markdown: markdown)
            case .questions(let questions):
                QuestionsView(request: request, session: session, questions: questions)
            }
        }
    }
}

private struct AgentPermissionView: View {
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
