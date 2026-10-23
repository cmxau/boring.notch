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
                VStack(alignment: .leading, spacing: 6) {
                    AgentSessionList(sessions: hub.orderedSessions, highlighted: hub.requests.first?.sessionID)
                    AgentUsageStrip()
                }
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
