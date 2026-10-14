import Foundation
import Observation

/// On-device event log answering "why did I miss a notification?": was the app suspended,
/// killed, or running? A 30 s heartbeat makes suspensions visible as gaps, and a missing
/// clean-exit marker at the next launch means iOS killed the process (or it crashed).
@MainActor
@Observable
final class DiagnosticsLog {
    static let shared = DiagnosticsLog()

    struct Entry: Codable, Identifiable {
        var id = UUID()
        let date: Date
        let text: String
    }

    private(set) var entries: [Entry] = []

    @ObservationIgnored private var heartbeat: Timer?
    @ObservationIgnored private var lastBeat: Date?

    private static let maxEntries = 500
    private static let heartbeatInterval: TimeInterval = 30
    private static let lastAliveKey = "diagnosticsLastAlive"
    private static let cleanExitKey = "diagnosticsCleanExit"

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("diagnostics.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    func log(_ text: String) {
        entries.append(Entry(date: Date(), text: text))
        if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
        persist()
    }

    /// Call once per process, from `didFinishLaunching`.
    func processStarted(_ details: String) {
        let defaults = UserDefaults.standard
        if let lastAlive = defaults.object(forKey: Self.lastAliveKey) as? Date,
           !defaults.bool(forKey: Self.cleanExitKey) {
            log("Previous process ended without notice – killed by iOS or crashed. Last sign of life: \(Self.format(lastAlive)).")
        }
        defaults.set(false, forKey: Self.cleanExitKey)
        log("Process started – \(details)")

        beat()
        heartbeat = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.beat() }
        }
    }

    func processTerminating() {
        log("iOS is terminating the app (applicationWillTerminate)")
        UserDefaults.standard.set(true, forKey: Self.cleanExitKey)
        UserDefaults.standard.set(Date(), forKey: Self.lastAliveKey)
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    var exportText: String {
        entries.map { "\(Self.format($0.date))  \($0.text)" }.joined(separator: "\n")
    }

    /// Timers don't fire while suspended, so a long gap between beats is a suspension.
    private func beat() {
        let now = Date()
        if let lastBeat, now.timeIntervalSince(lastBeat) > Self.heartbeatInterval * 3 {
            let minutes = Int(now.timeIntervalSince(lastBeat) / 60)
            log("Not running for ~\(minutes) min (\(Self.format(lastBeat)) → \(Self.format(now))) – iOS suspended the app")
        }
        lastBeat = now
        UserDefaults.standard.set(now, forKey: Self.lastAliveKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func format(_ date: Date) -> String { formatter.string(from: date) }
}
