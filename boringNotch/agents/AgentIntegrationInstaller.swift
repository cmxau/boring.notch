//
//  AgentIntegrationInstaller.swift
//  boringNotch
//
//  Adds Boring Notch's hooks to each installed AI agent's settings, so they report to the notch with no setup.
//  The file access goes through the XPC helper, since the sandboxed app can't reach the home folder.
//

import Defaults
import Foundation
import os

@MainActor
final class AgentIntegrationInstaller: ObservableObject {
    static let shared = AgentIntegrationInstaller()

    enum Status: Equatable {
        /// The agent doesn't seem to be installed on this Mac.
        case agentNotFound
        case notConnected
        case connected
        case failed(String)
    }

    /// Keyed by agent ID.
    @Published private(set) var statuses: [String: Status] = [:]

    private let logger = Logger(subsystem: "com.theboringteam.boringnotch", category: "AgentIntegration")
    private let helper = XPCHelperClient.shared

    static let bridgePath = ".boring-notch/bridge"

    func status(of kind: AgentKind) -> Status? {
        statuses[kind.id]
    }

    // MARK: - Bridge

    /// Writes the port and token the bridge script uses to reach the notch, and the script itself.
    func writeBridge(port: UInt16, token: String) async {
        if let contents = Self.bridgeScript {
            await writeIfChanged(AgentHookCommand.scriptPath, contents, executable: true)
        }
        await writeIfChanged(Self.bridgePath, Self.bridgeFile(port: port, token: token))
    }

    /// The bridge script bundled with the app.
    static var bridgeScript: Data? {
        Bundle.main.url(forResource: "boring-agent-hook", withExtension: "sh").flatMap { try? Data(contentsOf: $0) }
    }

    /// Contents of the bridge file. `host` names this machine for agents reaching the notch over SSH.
    static func bridgeFile(port: UInt16, token: String, host: String? = nil) -> Data {
        var text = "port=\(port)\ntoken=\(token)\n"
        if let host {
            text += "host=\(host)\n"
        }
        return Data(text.utf8)
    }

    // MARK: - Agents

    /// Connects every installed agent the user hasn't disconnected themselves.
    func installDetectedAgents() async {
        let disconnected = Set(Defaults[.agentIntegrationsDisconnected])
        for integration in AgentRegistry.integrations {
            let id = integration.kind.id
            guard await isInstalled(integration) else {
                statuses[id] = .agentNotFound
                continue
            }
            if disconnected.contains(id) {
                statuses[id] = .notConnected
            } else {
                statuses[id] = await update(integration, install: true)
            }
        }
    }

    func refreshStatuses() async {
        let disconnected = Set(Defaults[.agentIntegrationsDisconnected])
        for integration in AgentRegistry.integrations {
            let id = integration.kind.id
            if !(await isInstalled(integration)) {
                statuses[id] = .agentNotFound
            } else if disconnected.contains(id) {
                statuses[id] = .notConnected
            } else if case .failed = statuses[id] {
                continue
            } else {
                statuses[id] = .connected
            }
        }
    }

    func connect(_ kind: AgentKind) async {
        guard let integration = AgentRegistry.integration(id: kind.id) else { return }
        Defaults[.agentIntegrationsDisconnected].removeAll { $0 == kind.id }
        statuses[kind.id] = await update(integration, install: true)
    }

    func disconnect(_ kind: AgentKind) async {
        guard let integration = AgentRegistry.integration(id: kind.id) else { return }
        if !Defaults[.agentIntegrationsDisconnected].contains(kind.id) {
            Defaults[.agentIntegrationsDisconnected].append(kind.id)
        }
        let status = await update(integration, install: false)
        statuses[kind.id] = status == .connected ? .notConnected : status
    }

    private func isInstalled(_ integration: any AgentIntegration) async -> Bool {
        for path in integration.detectionPaths where await helper.agentFileExists(path) {
            return true
        }
        return false
    }

    private func update(_ integration: any AgentIntegration, install: Bool) async -> Status {
        var current: [String: Data] = [:]
        for file in integration.configFiles {
            if let data = await helper.readAgentFile(file) {
                current[file] = data
            }
        }

        do {
            let updated = try integration.updatedConfigFiles(current, install: install, hookExecutable: AgentHookCommand.executable)
            for (file, contents) in updated where contents != current[file] {
                if let error = await helper.writeAgentFile(file, contents: contents) {
                    logger.error("Couldn't update \(file, privacy: .public): \(error, privacy: .public)")
                    return .failed(error)
                }
            }
            return install ? .connected : .notConnected
        } catch {
            logger.error("Couldn't update \(integration.kind.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    @discardableResult
    private func writeIfChanged(_ path: String, _ contents: Data, executable: Bool = false) async -> String? {
        guard await helper.readAgentFile(path) != contents else { return nil }
        return await helper.writeAgentFile(path, contents: contents, executable: executable)
    }
}
