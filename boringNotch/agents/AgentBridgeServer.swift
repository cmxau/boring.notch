//
//  AgentBridgeServer.swift
//  boringNotch
//
//  A small HTTP server on the loopback interface that the hook bridge script (boring-agent-hook) posts agent
//  events to. Requests that need a decision are held open until the notch answers them.
//

import Foundation
import Network
import os

struct AgentHookRequest {
    /// Agent name from the URL path, e.g. "claude".
    let agent: String
    /// Hook event name, e.g. "PermissionRequest".
    let event: String
    /// Request headers, keyed in lowercase.
    let headers: [String: String]
    let body: Data

    var terminal: TerminalLocation {
        func value(_ name: String) -> String? {
            guard let value = headers[name], !value.isEmpty, value != "?" else { return nil }
            return value
        }
        return TerminalLocation(
            tty: value("x-terminal-tty"),
            program: value("x-terminal-program"),
            appBundleID: value("x-terminal-app"),
            sessionID: value("x-terminal-session"),
            tmuxPane: value("x-tmux-pane"),
            kittyWindow: value("x-kitty-window"),
            weztermPane: value("x-wezterm-pane")
        )
    }
}

/// Fires once if the agent stops waiting for an answer (its hook timed out or it was interrupted).
final class AgentRequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [() -> Void] = []

    func onCancel(_ handler: @escaping () -> Void) {
        lock.lock()
        if cancelled {
            lock.unlock()
            handler()
            return
        }
        handlers.append(handler)
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        let handlers = self.handlers
        self.handlers = []
        lock.unlock()
        handlers.forEach { $0() }
    }
}

final class AgentBridgeServer: @unchecked Sendable {
    typealias Handler = @Sendable (AgentHookRequest, AgentRequestCancellation) async -> Data

    private static let maximumRequestSize = 4 * 1024 * 1024

    private let logger = Logger(subsystem: "com.theboringteam.boringnotch", category: "AgentBridge")
    private let queue = DispatchQueue(label: "theboringteam.boringnotch.agent-bridge")
    private let token: String
    private let handler: Handler
    private var listener: NWListener?
    private var port: UInt16?

    /// Called on the main queue once the server is listening, with its port.
    var onReady: ((UInt16) -> Void)?

    init(token: String, handler: @escaping Handler) {
        self.token = token
        self.handler = handler
    }

    func start() throws {
        let parameters = NWParameters.tcp
        // Only reachable from this Mac
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters, on: .any)
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self else { return }
            switch state {
            case .ready:
                if let port = listener?.port?.rawValue {
                    self.port = port
                    DispatchQueue.main.async { self.onReady?(port) }
                }
            case .failed(let error):
                self.logger.error("Agent bridge stopped: \(error.localizedDescription, privacy: .public)")
                listener?.cancel()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data {
                buffer.append(data)
            }

            switch self.parse(buffer) {
            case .complete(let request):
                self.handle(request, on: connection)
            case .rejected(let status):
                self.send(status: status, body: Data(), on: connection)
            case .incomplete:
                if isComplete || error != nil {
                    connection.cancel()
                } else if buffer.count > Self.maximumRequestSize {
                    self.send(status: 413, body: Data(), on: connection)
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    private func handle(_ request: AgentHookRequest, on connection: NWConnection) {
        let cancellation = AgentRequestCancellation()
        // The bridge script keeps the connection open while it waits, so it closing means the agent gave up
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, isComplete, error in
            if isComplete || error != nil {
                cancellation.cancel()
            }
        }

        let handler = self.handler
        Task {
            let body = await handler(request, cancellation)
            self.queue.async {
                self.send(status: 200, body: body, on: connection)
            }
        }
    }

    private func send(status: Int, body: Data, on connection: NWConnection) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 413: reason = "Payload Too Large"
        default: reason = "Error"
        }
        let header = "HTTP/1.1 \(status) \(reason)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Parsing

    private enum ParseResult {
        case incomplete
        case complete(AgentHookRequest)
        case rejected(status: Int)
    }

    private func parse(_ buffer: Data) -> ParseResult {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        guard let head = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return .rejected(status: 400)
        }

        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2, requestLine[0] == "POST" else { return .rejected(status: 400) }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        // Browsers always send Origin on cross-site POSTs; agents never do. Checking Host as well stops DNS
        // rebinding, and the token stops other local processes from posting events.
        guard headers["origin"] == nil,
              let host = headers["host"], let port,
              host == "127.0.0.1:\(port)" || host == "localhost:\(port)",
              headers["x-boring-notch-token"] == token
        else { return .rejected(status: 403) }

        let path = String(requestLine[1])
        let prefix = "/v1/hooks/"
        guard path.hasPrefix(prefix) else { return .rejected(status: 404) }
        let agent = String(path.dropFirst(prefix.count))

        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length >= 0, length <= Self.maximumRequestSize else { return .rejected(status: 413) }
        let bodyStart = headerEnd.upperBound
        guard buffer.count - (bodyStart - buffer.startIndex) >= length else { return .incomplete }
        let body = buffer[bodyStart..<(bodyStart + length)]

        return .complete(AgentHookRequest(
            agent: agent,
            event: headers["x-agent-event"] ?? "",
            headers: headers,
            body: Data(body)
        ))
    }
}
