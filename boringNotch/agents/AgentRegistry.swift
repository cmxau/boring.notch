//
//  AgentRegistry.swift
//  boringNotch
//
//  Every AI agent the notch supports. To add one, write an `AgentIntegration` and list it here.
//

import Foundation

@MainActor
enum AgentRegistry {
    static let integrations: [any AgentIntegration] = [
        ClaudeStyleIntegration.claudeCode,
        CodexIntegration(),
        GeminiStyleIntegration.geminiCLI,
    ]

    static var kinds: [AgentKind] {
        integrations.map(\.kind)
    }

    static func integration(id: String) -> (any AgentIntegration)? {
        integrations.first { $0.kind.id == id }
    }
}
