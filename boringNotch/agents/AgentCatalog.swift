//
//  AgentCatalog.swift
//  boringNotch
//
//  The AI tools listed in Settings > AI Integrations, grouped into agents, desktop apps and IDEs. Tools with an
//  `AgentIntegration` can be connected; the others are listed as not supported yet.
//

import AppKit
import SwiftUI

enum AgentCatalog {
    enum Category: String, CaseIterable, Identifiable {
        case agents = "Agents"
        case desktopApps = "Desktop apps"
        case ides = "IDEs"

        var id: String { rawValue }
    }

    struct Entry: Identifiable {
        let name: String
        /// File name in boringNotch/agents/icons, without ".png".
        let icon: String
        let category: Category
        /// The `AgentKind` id of its integration, when there is one.
        var integrationID: String?

        var id: String { category.rawValue + ":" + name }
    }

    static let entries: [Entry] = [
        // Agents
        Entry(name: "Claude Code", icon: "claude-agent-icon", category: .agents, integrationID: "claude"),
        Entry(name: "Codex CLI", icon: "codex-agent-icon", category: .agents, integrationID: "codex"),
        Entry(name: "Gemini CLI", icon: "gemini-agent-icon", category: .agents, integrationID: "gemini"),
        Entry(name: "Amp", icon: "amp-agent-icon", category: .agents),
        Entry(name: "CodeBuddy", icon: "codebuddy-agent-icon", category: .agents, integrationID: "codebuddy"),
        Entry(name: "Copilot CLI", icon: "copilot-agent-icon", category: .agents, integrationID: "copilot"),
        Entry(name: "DeepSeek", icon: "deepseek-agent-icon", category: .agents),
        Entry(name: "Devin", icon: "devin-agent-icon", category: .agents),
        Entry(name: "Droid", icon: "droid-agent-icon", category: .agents, integrationID: "droid"),
        Entry(name: "Grok CLI", icon: "grok-agent-icon", category: .agents),
        Entry(name: "Hermes", icon: "hermes-agent-icon", category: .agents),
        Entry(name: "Kimi CLI", icon: "kimi-agent-icon", category: .agents),
        Entry(name: "Kimi Code", icon: "kimicode-agent-icon", category: .agents),
        Entry(name: "MiMo Code", icon: "mimocode-agent-icon", category: .agents),
        Entry(name: "Mistral Vibe", icon: "mistralvibe-agent-icon", category: .agents),
        Entry(name: "Oh My Pi", icon: "ohmypi-agent-icon", category: .agents),
        Entry(name: "OpenClaw", icon: "openclaw-agent-icon", category: .agents),
        Entry(name: "OpenCode", icon: "opencode-agent-icon", category: .agents, integrationID: "opencode"),
        Entry(name: "Pi", icon: "pi-agent-icon", category: .agents),
        Entry(name: "Qwen Code", icon: "qwen-agent-icon", category: .agents, integrationID: "qwen"),
        Entry(name: "dsh", icon: "dsh-agent-icon", category: .agents),
        Entry(name: "ZCode", icon: "zcode-agent-icon", category: .agents),
        // Desktop apps
        Entry(name: "Claude", icon: "claude-desktop-icon", category: .desktopApps),
        Entry(name: "Codex", icon: "codex-app-icon", category: .desktopApps),
        Entry(name: "Gemini", icon: "gemini-icon", category: .desktopApps),
        Entry(name: "Grok", icon: "grok-icon", category: .desktopApps),
        Entry(name: "Kimi", icon: "kimi-icon", category: .desktopApps),
        Entry(name: "Qoder Work", icon: "qoderwork-agent-icon", category: .desktopApps),
        Entry(name: "Qwen Work", icon: "qwenwork-agent-icon", category: .desktopApps),
        Entry(name: "WorkBuddy", icon: "workbuddy-agent-icon", category: .desktopApps),
        Entry(name: "Z.ai", icon: "zai-icon", category: .desktopApps),
        // IDEs
        Entry(name: "Antigravity", icon: "antigravity-icon", category: .ides, integrationID: "antigravity"),
        Entry(name: "Cursor", icon: "cursor-pixel", category: .ides, integrationID: "cursor"),
        Entry(name: "Kiro", icon: "kiro-agent-icon", category: .ides),
        Entry(name: "Qoder", icon: "qoder-agent-icon", category: .ides, integrationID: "qoder"),
        Entry(name: "Qoder CN", icon: "qodercn-agent-icon", category: .ides, integrationID: "qoder-cn"),
        Entry(name: "Trae", icon: "trae-agent-icon", category: .ides),
        Entry(name: "VS Code", icon: "vscodeagent-agent-icon", category: .ides),
    ]

    static func entries(in category: Category) -> [Entry] {
        entries.filter { $0.category == category }
    }

    /// The icon for an agent kind, from its catalog entry.
    static func icon(forKindID id: String) -> String? {
        entries.first { $0.integrationID == id }?.icon
    }

    private static var imageCache: [String: NSImage] = [:]

    static func image(_ icon: String) -> NSImage? {
        if let image = imageCache[icon] { return image }
        guard let url = Bundle.main.url(forResource: icon, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        imageCache[icon] = image
        return image
    }
}

/// An agent's icon from the catalog, or its SF Symbol when there's none.
struct AgentCatalogIcon: View {
    let icon: String?
    var symbol: String = "sparkles"
    var size: CGFloat = 20

    var body: some View {
        if let icon, let image = AgentCatalog.image(icon) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } else {
            Image(systemName: symbol)
                .frame(width: size, height: size)
        }
    }
}
