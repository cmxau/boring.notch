//
//  TerminalPanes.swift
//  BoringNotchXPCHelper
//
//  Focuses the exact tmux, kitty or WezTerm pane an agent runs in.
//

import Foundation

extension BoringNotchXPCHelper {
    @objc func focusTerminalPane(_ terminal: String, target: String, socket: String?, with reply: @escaping (Bool) -> Void) {
        // Not implemented yet
        reply(false)
    }
}
