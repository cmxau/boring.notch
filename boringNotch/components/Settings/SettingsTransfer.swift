//
//  SettingsTransfer.swift
//  boringNotch
//
//  Saves Boring Notch's settings to a file and loads them back, to move them to another Mac or keep a backup.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum SettingsTransfer {
    /// Kept out of exports: secrets, and state that only makes sense on this Mac.
    private static let excludedKeys: Set<String> = ["agentBridgeToken", "agentIntegrationsDisconnected"]
    private static let excludedPrefixes = ["NS", "Apple", "SU", "com.apple."]

    private static func isTransferable(_ key: String) -> Bool {
        !excludedKeys.contains(key) && !excludedPrefixes.contains { key.hasPrefix($0) }
    }

    static func exportSettings() {
        guard let domain = Bundle.main.bundleIdentifier,
              let settings = UserDefaults.standard.persistentDomain(forName: domain)
        else { return }
        let exported = settings.filter { isTransferable($0.key) }

        let panel = NSSavePanel()
        panel.title = "Export Settings"
        panel.nameFieldStringValue = "Boring Notch Settings.plist"
        panel.allowedContentTypes = [.propertyList]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: exported, format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
        } catch {
            showAlert("Couldn't export settings", error.localizedDescription)
        }
    }

    static func importSettings() {
        let panel = NSOpenPanel()
        panel.title = "Import Settings"
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            guard let settings = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                showAlert("Couldn't import settings", "The file isn't a Boring Notch settings file.")
                return
            }
            for (key, value) in settings where isTransferable(key) {
                UserDefaults.standard.set(value, forKey: key)
            }
        } catch {
            showAlert("Couldn't import settings", error.localizedDescription)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Settings imported"
        alert.informativeText = "Boring Notch needs to restart to use them."
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            ApplicationRelauncher.restart()
        }
    }

    private static func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
