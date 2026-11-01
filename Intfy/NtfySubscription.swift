import Foundation

/// Keeps a long-lived HTTP stream to `/<topics>/json` open and reconnects with backoff.
/// Resumes from the last seen server time (`since=`) so nothing is lost across drops.
///
/// Battery: every keepalive the server sends wakes the radio, so the idle timeout follows
/// the server's actual `keepalive-interval` (learned from the stream) instead of assuming
/// ntfy's 45 s default. Raising that interval on the server then directly saves battery.
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
    var onLog: (String) -> Void = { _ in }
    var since: () -> String? = { nil }
    /// Upper bound for the reconnect backoff. AppModel uses a longer one in the background,
    /// where a network change or returning to the app reconnects right away anyway.
    var maxRetryDelay: () -> TimeInterval = { 30 }

    private(set) var isRunning = false
    private var task: Task<Void, Never>?
    private var lastActivity = Date.distantPast

    /// ntfy's default `keepalive-interval`.
    static let defaultKeepalive: TimeInterval = 45
    static let maxKeepalive: TimeInterval = 15 * 60
    /// Never declare a socket dead sooner than this, whatever the keepalive.
    static let minIdleTimeout: TimeInterval = 100

    /// Current estimate of the server's keepalive interval. Survives reconnects (not restarts).
    private(set) var keepalive = defaultKeepalive

    /// No data for longer than this means a dead socket: two missed keepalives plus slack.
    var idleTimeout: TimeInterval { max(Self.minIdleTimeout, keepalive * 2 + 15) }

    /// True when the socket claims to be open but has been silent past the keepalive window
    /// (typically after the app was suspended).
    var isStale: Bool { isRunning && Date().timeIntervalSince(lastActivity) > idleTimeout }

    var isRetrying: Bool {
        if case .retrying = state { return true }
        return false
    }

    private var state: State = .idle {
        didSet { onState(state) }
    }

    func start(client: NtfyClient) {
        stop()
        isRunning = true
        task = Task { [weak self] in await self?.run(client) }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        state = .idle
    }

    /// One session per connection attempt, so its idle timeout matches the current estimate.
    private static func makeSession(idleTimeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = idleTimeout
        configuration.timeoutIntervalForResource = 60 * 60 * 24 * 365
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    private func run(_ client: NtfyClient) async {
        var delay: TimeInterval = 1
        while !Task.isCancelled {
            state = .connecting
            var connectedAt: Date?
            var sawKeepalive = false
            var lastBeat: Date?
            let timeout = idleTimeout
            let session = Self.makeSession(idleTimeout: timeout)
            do {
                defer { session.invalidateAndCancel() }
                let url = try client.subscribeURL(poll: false, since: since())
                let (bytes, response) = try await session.bytes(for: client.request(url, timeout: timeout))
                try NtfyClient.check(response)
                connectedAt = Date()
                lastActivity = Date()
                state = .connected
                for try await line in bytes.lines {
                    let now = Date()
                    lastActivity = now
                    guard let event = NtfyClient.decode(line) else { continue }
                    if event.event == "open" || event.event == "keepalive" {
                        if event.event == "keepalive" {
                            sawKeepalive = true
                            if let lastBeat { learnKeepalive(gap: now.timeIntervalSince(lastBeat), timeout: timeout) }
                        }
                        lastBeat = now
                    }
                    onEvent(event)
                }
                throw NtfyError.streamClosed(after: Date().timeIntervalSince(connectedAt!))
            } catch {
                if Task.isCancelled { return }
                if let connectedAt, !sawKeepalive, (error as? URLError)?.code == .timedOut {
                    // Connected, then silence until the timeout without a single keepalive: either
                    // a dead socket or a server keepalive longer than we assumed. Allow more next
                    // time; if it was a dead socket the next stream's keepalives correct it.
                    raiseKeepalive(after: Date().timeIntervalSince(connectedAt))
                }
                // Only a connection that actually held resets the backoff; otherwise a server that
                // accepts and immediately closes would be hammered once a second.
                if let connectedAt, Date().timeIntervalSince(connectedAt) > 30 { delay = 1 }
                state = .retrying(error.localizedDescription)
                if case NtfyError.notConfigured = error { return }
            }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            delay = min(delay * 2, max(1, maxRetryDelay()))
        }
    }

    /// ntfy sends `open` on connect and then a keepalive every interval, so the time between
    /// two of them is the configured interval, whatever messages came in between. Gaps beyond
    /// the timeout can only come from a suspension and are ignored.
    private func learnKeepalive(gap: TimeInterval, timeout: TimeInterval) {
        guard gap > 1, gap <= timeout else { return }
        let rounded = min(Self.maxKeepalive, (gap / 5).rounded() * 5)
        guard abs(rounded - keepalive) > max(5, keepalive * 0.2) else { return }
        keepalive = max(5, rounded)
        onLog("Server keepalive ≈ \(Int(keepalive)) s – idle timeout now \(Int(idleTimeout)) s")
    }

    private func raiseKeepalive(after silence: TimeInterval) {
        guard keepalive < Self.maxKeepalive else { return }
        keepalive = min(Self.maxKeepalive, max(keepalive * 2, silence))
        onLog("No keepalive within \(Int(silence)) s – allowing up to \(Int(idleTimeout)) s next time")
    }
}
