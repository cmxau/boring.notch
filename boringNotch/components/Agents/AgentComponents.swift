//
//  AgentComponents.swift
//  boringNotch
//
//  Pieces shared by the agent views: buttons, status icons and card headers.
//

import SwiftUI

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

struct AgentCardHeader: View {
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
