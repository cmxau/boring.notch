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
                ForEach(AgentCatalog.Category.allCases) { category in
                    Section {
                        let entries = AgentCatalog.entries(in: category)
                        let supported = entries.compactMap { entry in
                            entry.integrationID.flatMap { id in AgentRegistry.kinds.first { $0.id == id } }.map { (entry, $0) }
                        }
                        ForEach(Array(supported.enumerated()), id: \.offset) { _, pair in
                            AgentIntegrationRow(kind: pair.1, icon: pair.0.icon, status: installer.status(of: pair.1))
                        }
                        let unsupported = entries.filter { $0.integrationID == nil }
                        if !unsupported.isEmpty {
                            UnsupportedAgentsGrid(entries: unsupported)
                        }
                    } header: {
                        Text(category.rawValue)
                    } footer: {
                        if category == .agents {
                            Text("Connecting adds Boring Notch's hooks to the tool's settings (a backup of the original is kept next to it). Your own hooks are left alone.")
                                .foregroundStyle(.secondary)
                        } else if category == .ides {
                            Text("Antigravity's connection covers its IDE, desktop app and agy CLI.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Defaults.Toggle(key: .agentOpenNotchOnRequest) {
                        Text("Open the notch when an agent needs you")
                    }
                    Defaults.Toggle(key: .agentShowInClosedNotch) {
                        Text("Show agent activity in the closed notch")
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

                AgentSoundSettingsSection()
                AgentUsageSettingsSection()
                AgentRemoteSettingsSection()
                AgentTerminalSettingsSection()
            }
        }
        .navigationTitle("AI Integrations")
        .task {
            await installer.refreshStatuses()
        }
    }
}

/// Tools that can't be connected yet, as a wrapped grid of icons.
private struct UnsupportedAgentsGrid: View {
    let entries: [AgentCatalog.Entry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not supported yet")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(entries) { entry in
                    HStack(spacing: 6) {
                        AgentCatalogIcon(icon: entry.icon, size: 16)
                        Text(entry.name)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .opacity(0.6)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AgentIntegrationRow: View {
    let kind: AgentKind
    let icon: String?
    let status: AgentIntegrationInstaller.Status?

    var body: some View {
        HStack {
            AgentCatalogIcon(icon: icon, symbol: kind.symbol, size: 22)
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
            return "Connected: " + capabilitiesDescription
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

    private var capabilitiesDescription: String {
        var parts = ["status"]
        if kind.capabilities.contains(.approvals) { parts.append("approvals") }
        if kind.capabilities.contains(.questions) { parts.append("questions") }
        if kind.capabilities.contains(.plans) { parts.append("plans") }
        return ListFormatter.localizedString(byJoining: parts)
    }

    private var detailColor: Color {
        switch status {
        case .connected: return .green
        case .failed: return .red
        default: return .secondary
        }
    }
}
