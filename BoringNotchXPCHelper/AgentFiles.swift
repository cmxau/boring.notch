//
//  AgentFiles.swift
//  BoringNotchXPCHelper
//
//  Reads and writes AI agents' hook settings on behalf of the sandboxed app. Only the agents' own config files
//  and Boring Notch's bridge files can be touched.
//

import Foundation

extension BoringNotchXPCHelper {
    private static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    @objc func agentFileExists(_ path: String, with reply: @escaping (Bool) -> Void) {
        guard AgentFileAllowlist.canCheck(path) else {
            reply(false)
            return
        }
        reply(FileManager.default.fileExists(atPath: Self.home.appendingPathComponent(path).path))
    }

    @objc func readAgentFile(_ path: String, with reply: @escaping (Data?) -> Void) {
        guard AgentFileAllowlist.canRead(path) else {
            reply(nil)
            return
        }
        reply(try? Data(contentsOf: Self.home.appendingPathComponent(path)))
    }

    @objc func writeAgentFile(_ path: String, contents: Data, executable: Bool, with reply: @escaping (String?) -> Void) {
        guard AgentFileAllowlist.canWrite(path) else {
            reply("Not allowed to write \(path)")
            return
        }

        let fileManager = FileManager.default
        // Write through symlinks (settings kept in a dotfiles repo, for example) rather than replacing them
        let url = Self.home.appendingPathComponent(path).resolvingSymlinksInPath()
        let isOwnFile = path.hasPrefix(".boring-notch/")

        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

            let existingPermissions = (try? fileManager.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int

            // Keep a copy of the agent's settings from before Boring Notch first changed them
            if !isOwnFile, fileManager.fileExists(atPath: url.path) {
                let backup = url.appendingPathExtension("boring-notch-backup")
                if !fileManager.fileExists(atPath: backup.path) {
                    try fileManager.copyItem(at: url, to: backup)
                }
            }

            try contents.write(to: url, options: .atomic)

            // The bridge file holds the access token, so only this user may read it. Agent settings keep
            // whatever permissions they had.
            let permissions: Int = executable ? 0o755 : (isOwnFile ? 0o600 : existingPermissions ?? 0o644)
            try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
            reply(nil)
        } catch {
            reply(error.localizedDescription)
        }
    }

    @objc func listAgentDirectory(_ path: String, with reply: @escaping ([String]?) -> Void) {
        guard AgentFileAllowlist.canList(path) else {
            reply(nil)
            return
        }
        reply(try? FileManager.default.contentsOfDirectory(atPath: Self.home.appendingPathComponent(path).path))
    }
}
