import Foundation

/// One line of ntfy's JSON stream (`/<topics>/json`). Events: open, keepalive, message, poll_request.
struct NtfyMessage: Codable, Identifiable, Hashable {
    struct Attachment: Codable, Hashable {
        var name: String
        var url: String
        var type: String?
    }

    var id: String
    var time: Int
    var event: String
    var topic: String
    var message: String?
    var title: String?
    var priority: Int?
    var tags: [String]?
    var click: String?
    var attachment: Attachment?
    /// Which configured server delivered it. Not part of ntfy's JSON; set on receipt.
    var serverID: UUID?

    var isMessage: Bool { event == "message" }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(time)) }
    var effectivePriority: Int { priority ?? 3 }

    var emojiTags: [String] { (tags ?? []).compactMap { Self.emoji[$0] } }
    var textTags: [String] { (tags ?? []).filter { Self.emoji[$0] == nil } }

    /// The sending service – whatever it put in `title` (e.g. "Proxmox", "Uptime Kuma").
    var service: String? { title?.isEmpty == false ? title : nil }

    /// In-app row title: emoji tags + service, falling back to the topic.
    var displayTitle: String { withEmoji(service ?? topic) }

    /// Notification header: `<service> | <topic> | <server>`; parts that are missing are skipped.
    func notificationHeader(serverName: String?) -> String {
        withEmoji([service, topic, serverName].compactMap { $0 }.joined(separator: " | "))
    }

    private func withEmoji(_ text: String) -> String {
        let prefix = emojiTags.joined()
        return prefix.isEmpty ? text : "\(prefix) \(text)"
    }

    var notificationBody: String {
        var body = message ?? ""
        if let attachment { body += (body.isEmpty ? "" : "\n") + "📎 \(attachment.name)" }
        return body
    }

    var clickURL: URL? { click.flatMap(URL.init(string:)) }

    /// Subset of the emoji short codes ntfy turns into emoji (https://docs.ntfy.sh/emojis/).
    static let emoji: [String: String] = [
        "+1": "👍", "-1": "👎", "warning": "⚠️", "rotating_light": "🚨", "triangular_flag_on_post": "🚩",
        "skull": "💀", "facepalm": "🤦", "no_entry": "⛔", "no_entry_sign": "🚫", "cd": "💿",
        "loudspeaker": "📢", "white_check_mark": "✅", "heavy_check_mark": "✔️", "x": "❌",
        "tada": "🎉", "partying_face": "🥳", "bell": "🔔", "fire": "🔥", "rocket": "🚀",
        "computer": "💻", "floppy_disk": "💾", "package": "📦", "lock": "🔒", "unlock": "🔓",
        "key": "🔑", "zap": "⚡", "bug": "🐛", "hammer": "🔨", "wrench": "🔧", "gear": "⚙️",
        "heart": "❤️", "star": "⭐", "sparkles": "✨", "mailbox": "📫", "email": "📧",
        "calendar": "📅", "hourglass": "⌛", "thermometer": "🌡️", "sunny": "☀️", "cloud": "☁️",
        "umbrella": "☂️", "snowflake": "❄️", "house": "🏠", "car": "🚗", "moneybag": "💰",
        "chart_with_upwards_trend": "📈", "chart_with_downwards_trend": "📉", "eyes": "👀",
        "ghost": "👻", "robot": "🤖", "information_source": "ℹ️", "question": "❓",
        "exclamation": "❗", "stop_sign": "🛑", "battery": "🔋", "electric_plug": "🔌",
        "globe_with_meridians": "🌐", "satellite": "📡", "video_camera": "📹", "camera": "📷",
        "door": "🚪", "bulb": "💡", "speech_balloon": "💬", "link": "🔗", "inbox_tray": "📥",
        "outbox_tray": "📤", "green_circle": "🟢", "red_circle": "🔴", "yellow_circle": "🟡",
        "large_blue_circle": "🔵", "dog": "🐶", "cat": "🐱", "whale": "🐳", "penguin": "🐧",
    ]
}
