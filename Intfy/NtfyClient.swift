import Foundation

enum NtfyError: LocalizedError {
    case notConfigured
    case http(Int)
    case streamClosed(after: TimeInterval)
    case unhealthy

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Server address or topics missing"
        case .http(401), .http(403): "Unauthorized (HTTP 401/403) – check your username or token"
        case .http(404): "Not found (HTTP 404) – is this an ntfy server?"
        case .http(let code): "Server returned HTTP \(code)"
        case .unhealthy: "Server reports it is not healthy"
        case .streamClosed(let seconds): "Server closed the connection after \(Self.duration(seconds))"
        }
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        seconds < 90 ? "\(Int(seconds)) s" : "\(Int(seconds / 60)) min"
    }
}

/// Builds requests against a self-hosted ntfy server. Stateless; see `NtfySubscription` for the live stream.
struct NtfyClient {
    let config: ServerConfig
    let secret: String?

    func subscribeURL(poll: Bool, since: String?) throws -> URL {
        guard let base = config.baseURL, !config.topics.isEmpty else { throw NtfyError.notConfigured }
        let url = base
            .appendingPathComponent(config.topics.joined(separator: ","))
            .appendingPathComponent("json")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = []
        if poll { items.append(URLQueryItem(name: "poll", value: "1")) }
        if let since { items.append(URLQueryItem(name: "since", value: since)) }
        components.queryItems = items.isEmpty ? nil : items
        return components.url!
    }

    func request(_ url: URL, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        return request
    }

    private var authorization: String? {
        guard let secret, !secret.isEmpty else { return nil }
        switch config.authMode {
        case .none: return nil
        case .token: return "Bearer \(secret)"
        case .basic: return "Basic " + Data("\(config.username):\(secret)".utf8).base64EncodedString()
        }
    }

    /// One-shot fetch of cached messages — used when woken in the background and the stream is down.
    func poll(since: String) async throws -> [NtfyMessage] {
        let url = try subscribeURL(poll: true, since: since)
        let (data, response) = try await URLSession.shared.data(for: request(url, timeout: 20))
        try Self.check(response)
        return data.split(separator: UInt8(ascii: "\n")).compactMap { Self.decode(Data($0)) }
    }

    /// `GET /v1/health` — reachability only, no auth needed. Returns the round-trip time.
    func health() async throws -> TimeInterval {
        guard let base = config.baseURL else { throw NtfyError.notConfigured }
        struct Health: Decodable { let healthy: Bool }
        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: request(base.appending(path: "v1/health"), timeout: 10))
        try Self.check(response)
        guard (try? JSONDecoder().decode(Health.self, from: data))?.healthy == true else { throw NtfyError.unhealthy }
        return Date().timeIntervalSince(start)
    }

    func publish(topic: String, title: String, message: String) async throws {
        guard let base = config.baseURL else { throw NtfyError.notConfigured }
        var request = request(base, timeout: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "topic": topic, "title": title, "message": message, "tags": ["bell"],
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        try Self.check(response)
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else { throw NtfyError.http(http.statusCode) }
    }

    private static let decoder = JSONDecoder()

    static func decode(_ line: Data) -> NtfyMessage? {
        try? decoder.decode(NtfyMessage.self, from: line)
    }

    static func decode(_ line: String) -> NtfyMessage? {
        decode(Data(line.utf8))
    }
}
