import Foundation
import Observation
import UIKit

/// On-device event log answering "why did I miss a notification?": was the app suspended,
/// killed, or running? A 60 s heartbeat makes suspensions visible as gaps, and a missing
/// clean-exit marker at the next launch means iOS killed the process (or it crashed).
/// It also records battery drain while unplugged, so the cost of the keep-alives is measurable.
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
    @ObservationIgnored private var batteryMark: (date: Date, level: Float)?
    @ObservationIgnored private var batteryObservers: [NSObjectProtocol] = []

    private static let maxEntries = 500
    /// Each beat is a CPU wake-up; 60 s with tolerance still shows any real suspension.
    private static let heartbeatInterval: TimeInterval = 60
    /// Log battery drain in steps of this many percent while unplugged.
    private static let batteryStep: Float = 0.05
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
        let timer = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.beat() }
        }
        // Lets iOS batch this wake-up with others (network, audio, location).
        timer.tolerance = 15
        heartbeat = timer
        startBatteryTracking()
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

    // MARK: Battery

    /// Whole-device drain while unplugged, logged every 5 %, e.g. "Battery 80 % – used 5 % in 3 h 10 min
    /// (1.6 %/h)". Comparing these rates with a keep-alive on and off shows what it costs.
    private func startBatteryTracking() {
        guard batteryObservers.isEmpty else { return }
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let center = NotificationCenter.default
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
            batteryObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let stateChanged = note.name == UIDevice.batteryStateDidChangeNotification
                MainActor.assumeIsolated { self?.batteryChanged(stateChanged: stateChanged) }
            })
        }
        batteryChanged(stateChanged: false)
    }

    private func batteryChanged(stateChanged: Bool) {
        let device = UIDevice.current
        let level = device.batteryLevel
        guard level >= 0 else { return }
        let percent = Int((level * 100).rounded())
        guard device.batteryState == .unplugged else {
            if stateChanged && batteryMark != nil { log("Charger connected at \(percent) %") }
            batteryMark = nil
            return
        }
        guard let mark = batteryMark else {
            if stateChanged { log("Unplugged at \(percent) %") }
            batteryMark = (Date(), level)
            return
        }
        let used = mark.level - level
        guard used >= Self.batteryStep - 0.001 else { return }
        let elapsed = Date().timeIntervalSince(mark.date)
        let rate = Double(used * 100) / max(elapsed / 3600, 1.0 / 60)
        log("Battery \(percent) % – used \(Int((used * 100).rounded())) % in \(Self.duration(elapsed)) (\(String(format: "%.1f", rate)) %/h, whole phone)")
        batteryMark = (Date(), level)
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
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
