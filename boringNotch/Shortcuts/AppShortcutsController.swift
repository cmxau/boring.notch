//
//  AppShortcutsController.swift
//  boringNotch
//
//  The keyboard shortcuts for AI integrations and music. Request shortcuts (approve, deny, jump to terminal) are
//  only registered while an agent is waiting, so ⌃Y, ⌃N and ⌃T keep working in other apps the rest of the time.
//  "Enable keyboard shortcuts" turns every Boring Notch shortcut off without clearing them.
//

import Combine
import Defaults
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let agentApprove = Self("agentApprove", default: .init(.y, modifiers: [.control]))
    static let agentDeny = Self("agentDeny", default: .init(.n, modifiers: [.control]))
    static let agentJumpToTerminal = Self("agentJumpToTerminal", default: .init(.t, modifiers: [.control]))
    /// ⌃< and ⌃>: the comma and period keys
    static let musicPreviousTrack = Self("musicPreviousTrack", default: .init(.comma, modifiers: [.control]))
    static let musicNextTrack = Self("musicNextTrack", default: .init(.period, modifiers: [.control]))

    static let agentRequestShortcuts: [Self] = [.agentApprove, .agentDeny, .agentJumpToTerminal]
    static let alwaysOnShortcuts: [Self] = [
        .musicPreviousTrack, .musicNextTrack, .toggleSneakPeek, .toggleNotchOpen,
    ]
}

@MainActor
final class AppShortcutsController {
    static let shared = AppShortcutsController()

    private var cancellables: Set<AnyCancellable> = []

    func start() {
        KeyboardShortcuts.onKeyDown(for: .agentApprove) {
            Task { @MainActor in AgentHub.shared.answerFirstRequest(approve: true) }
        }
        KeyboardShortcuts.onKeyDown(for: .agentDeny) {
            Task { @MainActor in AgentHub.shared.answerFirstRequest(approve: false) }
        }
        KeyboardShortcuts.onKeyDown(for: .agentJumpToTerminal) {
            Task { @MainActor in AgentHub.shared.jumpToWaitingSession() }
        }
        KeyboardShortcuts.onKeyDown(for: .musicPreviousTrack) {
            Task { @MainActor in MusicManager.shared.previousTrack() }
        }
        KeyboardShortcuts.onKeyDown(for: .musicNextTrack) {
            Task { @MainActor in MusicManager.shared.nextTrack() }
        }

        AgentHub.shared.$requests
            .map { !$0.isEmpty }
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.apply() }
            }
            .store(in: &cancellables)
        Defaults.publisher(.keyboardShortcutsEnabled)
            .sink { [weak self] _ in
                Task { @MainActor in self?.apply() }
            }
            .store(in: &cancellables)
        apply()
    }

    private func apply() {
        let enabled = Defaults[.keyboardShortcutsEnabled]
        let agentWaiting = !AgentHub.shared.requests.isEmpty
        set(KeyboardShortcuts.Name.alwaysOnShortcuts, enabled: enabled)
        set(KeyboardShortcuts.Name.agentRequestShortcuts, enabled: enabled && agentWaiting)
    }

    private func set(_ names: [KeyboardShortcuts.Name], enabled: Bool) {
        if enabled {
            KeyboardShortcuts.enable(names)
        } else {
            KeyboardShortcuts.disable(names)
        }
    }
}
