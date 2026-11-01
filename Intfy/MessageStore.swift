import Foundation
import Observation

/// Received messages (shown in the app), IDs already notified about, and a `since` cursor per server.
@MainActor
@Observable
final class MessageStore {
    private(set) var messages: [NtfyMessage] = []

    @ObservationIgnored private var seenOrder: [String]
    @ObservationIgnored private var seen: Set<String>
    @ObservationIgnored private var cursors: [String: Int]
    @ObservationIgnored private var cursorsDirty = false
    @ObservationIgnored private var cursorsSavedAt = Date.distantPast

    private static let maxMessages = 300
    private static let maxSeen = 2000
    private static let seenKey = "seenMessageIDs"
    private static let cursorsKey = "sinceCursors"
    private static let legacyCursorKey = "sinceCursor"
    /// Keepalives advance the cursor every ~45 s; writing it each time is pointless disk work.
    /// A cursor a few minutes old only means a slightly larger catch-up after a crash —
    /// duplicates are dropped by ID, so nothing is lost or notified twice.
    private static let cursorSaveInterval: TimeInterval = 5 * 60

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("messages.json")
    }()

    init() {
        let defaults = UserDefaults.standard
        seenOrder = defaults.stringArray(forKey: Self.seenKey) ?? []
        seen = Set(seenOrder)
        cursors = defaults.dictionary(forKey: Self.cursorsKey) as? [String: Int] ?? [:]
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([NtfyMessage].self, from: data) {
            messages = saved
        }
    }

    /// Value for `since=`. One second of overlap; duplicates are dropped by ID.
    func sinceParameter(for server: UUID) -> String? {
        cursors[server.uuidString].map { String(max(0, $0 - 1)) }
    }

    /// Every event (open/keepalive/message) carries server time; following it means a
    /// reconnect asks only for what was published after the stream was last known alive.
    func advanceCursor(for server: UUID, to time: Int) {
        guard time > (cursors[server.uuidString] ?? 0) else { return }
        cursors[server.uuidString] = time
        cursorsDirty = true
        if Date().timeIntervalSince(cursorsSavedAt) > Self.cursorSaveInterval { saveCursors() }
    }

    func resetCursor(for server: UUID) {
        cursors[server.uuidString] = nil
        saveCursors()
    }

    /// Writes pending cursor changes; also called when going to the background or terminating.
    func saveCursors() {
        cursorsDirty = false
        cursorsSavedAt = Date()
        UserDefaults.standard.set(cursors, forKey: Self.cursorsKey)
    }

    func saveCursorsIfNeeded() {
        if cursorsDirty { saveCursors() }
    }

    /// Carries the single-server cursor over to the server migrated from the old config.
    func migrateLegacyCursor(to server: UUID) {
        let defaults = UserDefaults.standard
        if let legacy = defaults.object(forKey: Self.legacyCursorKey) as? Int {
            advanceCursor(for: server, to: legacy)
            defaults.removeObject(forKey: Self.legacyCursorKey)
        }
    }

    /// Messages received before multi-server support belong to the migrated server.
    func adoptUnassignedMessages(into server: UUID) {
        guard messages.contains(where: { $0.serverID == nil }) else { return }
        for index in messages.indices where messages[index].serverID == nil {
            messages[index].serverID = server
        }
        persist()
    }

    /// Returns false for messages we already handled (reconnect overlap, poll + stream race).
    func insertIfNew(_ message: NtfyMessage) -> Bool {
        guard !seen.contains(message.id) else { return false }
        seen.insert(message.id)
        seenOrder.append(message.id)
        if seenOrder.count > Self.maxSeen {
            let overflow = seenOrder.count - Self.maxSeen
            seenOrder.prefix(overflow).forEach { seen.remove($0) }
            seenOrder.removeFirst(overflow)
        }
        UserDefaults.standard.set(seenOrder, forKey: Self.seenKey)
        saveCursorsIfNeeded()

        let index = messages.firstIndex { $0.time < message.time } ?? messages.endIndex
        messages.insert(message, at: index)
        if messages.count > Self.maxMessages { messages.removeLast(messages.count - Self.maxMessages) }
        persist()
        return true
    }

    func delete(_ message: NtfyMessage) {
        messages.removeAll { $0.id == message.id }
        persist()
    }

    func clear() {
        messages.removeAll()
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(messages) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
