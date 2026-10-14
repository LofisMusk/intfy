import Foundation
import Security

enum AuthMode: String, Codable, CaseIterable, Identifiable {
    case none, token, basic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "None"
        case .token: "Token"
        case .basic: "Username & password"
        }
    }
}

struct ServerConfig: Codable, Equatable, Identifiable {
    var id = UUID()
    /// Optional nickname shown instead of the address, e.g. "Home" for 192.168.1.10.
    var name = ""
    var host: String = ""
    var port: Int?
    var useTLS = false
    var topics: [String] = []
    var authMode: AuthMode = .none
    var username = ""

    init() {}

    /// Tolerates configs saved before `id`/`name` existed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        useTLS = try c.decodeIfPresent(Bool.self, forKey: .useTLS) ?? false
        topics = try c.decodeIfPresent([String].self, forKey: .topics) ?? []
        authMode = try c.decodeIfPresent(AuthMode.self, forKey: .authMode) ?? .none
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
    }

    var isComplete: Bool { baseURL != nil && !topics.isEmpty }

    /// Nickname if set, otherwise the host.
    var displayName: String {
        let nickname = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nickname.isEmpty { return nickname }
        return baseURL?.host() ?? (host.isEmpty ? "New Server" : host)
    }

    /// Keychain account holding this server's token or password.
    var secretAccount: String { id.uuidString }

    /// Accepts "192.168.1.10", "ntfy.lan", "192.168.1.10:8080", "http://host/", "fd00::1".
    var baseURL: URL? {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        var scheme = useTLS ? "https" : "http"
        for prefix in ["http://", "https://"] where h.lowercased().hasPrefix(prefix) {
            scheme = String(prefix.dropLast(3))
            h.removeFirst(prefix.count)
        }
        if let slash = h.firstIndex(of: "/") { h = String(h[..<slash]) }
        guard !h.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.port = port

        let colons = h.filter { $0 == ":" }.count
        if colons == 1, let idx = h.firstIndex(of: ":") {
            // host:port typed into the host field
            if let p = Int(h[h.index(after: idx)...]) { components.port = p }
            h = String(h[..<idx])
        }
        if colons > 1 && !h.hasPrefix("[") {
            components.percentEncodedHost = "[\(h)]"
        } else {
            components.host = h
        }
        return components.url
    }

    /// Changes to this mean the stored `since` cursor no longer applies.
    var endpointKey: String { "\(baseURL?.absoluteString ?? "")|\(topics.joined(separator: ","))" }

    static func parseTopics(_ text: String) -> [String] {
        text.split(whereSeparator: { ", ;\n".contains($0) }).map(String.init)
    }

    static func isValidTopic(_ topic: String) -> Bool {
        topic.range(of: #"^[-_A-Za-z0-9]{1,64}$"#, options: .regularExpression) != nil
    }

    private static let serversKey = "servers"
    private static let legacyConfigKey = "serverConfig"
    private static let legacySecretAccount = "secret"

    /// Loads all servers. On first run after the multi-server update, the single legacy
    /// config (and its Keychain secret) becomes the first server; `migrated` reports it so the
    /// caller can carry over its `since` cursor.
    static func loadAll() -> (servers: [ServerConfig], migrated: ServerConfig?) {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: serversKey),
           let servers = try? JSONDecoder().decode([ServerConfig].self, from: data) {
            saveAll(servers)  // pins ids generated for entries saved without one
            return (servers, nil)
        }
        guard let data = defaults.data(forKey: legacyConfigKey),
              let legacy = try? JSONDecoder().decode(ServerConfig.self, from: data),
              !legacy.host.isEmpty
        else { return ([], nil) }

        if let secret = Keychain.get(legacySecretAccount) {
            Keychain.set(secret, for: legacy.secretAccount)
            Keychain.set(nil, for: legacySecretAccount)
        }
        saveAll([legacy])
        defaults.removeObject(forKey: legacyConfigKey)
        return ([legacy], legacy)
    }

    static func saveAll(_ servers: [ServerConfig]) {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: serversKey)
        }
    }
}

/// Stores the token / password. Readable after first unlock so background reconnects work.
enum Keychain {
    private static let service = "dev.intfy.credentials"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var attributes = base
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
