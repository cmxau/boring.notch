//
//  SSHTunnels.swift
//  BoringNotchXPCHelper
//
//  SSH reverse tunnels that let agents on remote servers reach the notch, and access to the agents' hook files
//  on those servers.
//

import Foundation

extension BoringNotchXPCHelper {
    @objc func startSSHTunnel(_ host: String, remotePort: Int, localPort: Int, with reply: @escaping (String?) -> Void) {
        reply("Not implemented yet")
    }

    @objc func stopSSHTunnel(_ host: String) {}

    @objc func sshTunnelStatus(_ host: String, with reply: @escaping (Bool, String) -> Void) {
        reply(false, "")
    }

    @objc func remoteAgentFileExists(_ host: String, path: String, with reply: @escaping (Bool) -> Void) {
        reply(false)
    }

    @objc func readRemoteAgentFile(_ host: String, path: String, with reply: @escaping (Data?) -> Void) {
        reply(nil)
    }

    @objc func writeRemoteAgentFile(_ host: String, path: String, contents: Data, executable: Bool, with reply: @escaping (String?) -> Void) {
        reply("Not implemented yet")
    }

    @objc func remoteHomeDirectory(_ host: String, with reply: @escaping (String?) -> Void) {
        reply(nil)
    }
}
