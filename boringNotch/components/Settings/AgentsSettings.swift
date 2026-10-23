//
//  AgentsSettings.swift
//  boringNotch
//
//  Settings for the AI agents integration.
//

import Defaults
import SwiftUI

struct AgentsSettings: View {
    @Default(.agentIntegrationEnabled) var agentIntegrationEnabled
    @Default(.agentDecisionTimeout) var agentDecisionTimeout
    @ObservedObject private var installer = AgentIntegrationInstaller.shared

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .agentIntegrationEnabled) {
                    Text("Show AI agents in the notch")
                }
            } footer: {
                Text("Agents report to the notch through their hooks, over a connection that never leaves this Mac.")
                    .foregroundStyle(.secondary)
            }

            if agentIntegrationEnabled {
                Section {
                    ForEach(AgentKind.allCases) { kind in
                        AgentIntegrationRow(kind: kind, status: installer.statuses[kind])
                    }
                } header: {
                    Text("Agents")
                } footer: {
                    Text("Connecting adds Boring Notch's hooks to the agent's settings (a backup of the original is kept next to it). Your own hooks are left alone.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Defaults.Toggle(key: .agentOpenNotchOnRequest) {
                        Text("Open the notch when an agent needs you")
                    }
                    Defaults.Toggle(key: .agentShowInClosedNotch) {
                        Text("Show agent activity in the closed notch")
                    }
                    Defaults.Toggle(key: .agentSoundsEnabled) {
                        Text("Play sounds")
                    }
                    Picker("Hand unanswered requests back to the terminal", selection: $agentDecisionTimeout) {
                        Text("After 1 minute").tag(60.0)
                        Text("After 5 minutes").tag(300.0)
                        Text("After 15 minutes").tag(900.0)
                        Text("Never").tag(0.0)
                    }
                } header: {
                    Text("Behavior")
                }
            }
        }
        .navigationTitle("Agents")
        .task {
            await installer.refreshStatuses()
        }
    }
}

private struct AgentIntegrationRow: View {
    let kind: AgentKind
    let status: AgentIntegrationInstaller.Status?

    var body: some View {
        HStack {
            Image(systemName: kind.symbol)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(detailColor)
            }
            Spacer()
            switch status {
            case .connected:
                Button("Disconnect") {
                    Task { await AgentIntegrationInstaller.shared.disconnect(kind) }
                }
            case .notConnected, .failed:
                Button("Connect") {
                    Task { await AgentIntegrationInstaller.shared.connect(kind) }
                }
            case .agentNotFound, .none:
                EmptyView()
            }
        }
    }

    private var detail: String {
        switch status {
        case .connected:
            return kind.supportsDecisions ? "Connected: status, approvals, questions and plans" : "Connected: status only"
        case .notConnected:
            return "Not connected"
        case .failed(let message):
            return message
        case .agentNotFound:
            return "Not installed"
        case .none:
            return "Checking…"
        }
    }

    private var detailColor: Color {
        switch status {
        case .connected: return .green
        case .failed: return .red
        default: return .secondary
        }
    }
}
