import Foundation

/// Keeps a long-lived HTTP stream to `/<topics>/json` open and reconnects with backoff.
/// Resumes from the last seen server time (`since=`) so nothing is lost across drops.
@MainActor
final class NtfySubscription {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case retrying(String)
    }

    var onState: (State) -> Void = { _ in }
    var onEvent: (NtfyMessage) -> Void = { _ in }
    var since: () -> String? = { nil }

    private(set) var isRunning = false
    private var task: Task<Void, Never>?
    private var lastActivity = Date.distantPast
    private let session: URLSession

    /// ntfy sends a keepalive every 45 s by default; no data for longer than this means a dead socket.
    static let idleTimeout: TimeInterval = 100

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Self.idleTimeout
        configuration.timeoutIntervalForResource = 60 * 60 * 24 * 365
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    /// True when the socket claims to be open but has been silent past the keepalive window
    /// (typically after the app was suspended).
    var isStale: Bool { isRunning && Date().timeIntervalSince(lastActivity) > Self.idleTimeout }

    func start(client: NtfyClient) {
        stop()
        isRunning = true
        task = Task { [weak self] in await self?.run(client) }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        onState(.idle)
    }

    private func run(_ client: NtfyClient) async {
        var delay: UInt64 = 1
        while !Task.isCancelled {
            onState(.connecting)
            var connectedAt: Date?
            do {
                let url = try client.subscribeURL(poll: false, since: since())
                let (bytes, response) = try await session.bytes(for: client.request(url, timeout: Self.idleTimeout))
                try NtfyClient.check(response)
                connectedAt = Date()
                lastActivity = Date()
                onState(.connected)
                for try await line in bytes.lines {
                    lastActivity = Date()
                    if let event = NtfyClient.decode(line) { onEvent(event) }
                }
                throw NtfyError.streamClosed(after: Date().timeIntervalSince(connectedAt!))
            } catch {
                if Task.isCancelled { return }
                // Only a connection that actually held resets the backoff; otherwise a server that
                // accepts and immediately closes would be hammered once a second.
                if let connectedAt, Date().timeIntervalSince(connectedAt) > 30 { delay = 1 }
                onState(.retrying(error.localizedDescription))
                if case NtfyError.notConfigured = error { return }
            }
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            delay = min(delay * 2, 30)
        }
    }
}
