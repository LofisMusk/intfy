import CoreLocation
import UIKit

/// Builds a prefilled GitHub "new issue" URL. Nothing is sent from the app: the user reviews
/// the issue on GitHub and submits it there.
@MainActor
struct BugReport {
    static let newIssueURL = "https://github.com/LofisMusk/intfy/issues/new"
    /// GitHub rejects very long URLs (~8 KB); keep the whole thing well below that.
    private static let maxURLLength = 7500

    var title: String
    var description: String
    var includeDiagnostics: Bool

    func url(model: AppModel) -> URL? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = DiagnosticsLog.shared.entries
        // Start with the last 40 log lines and drop the oldest until the URL fits.
        var lines = includeDiagnostics ? 40 : 0
        while true {
            let url = Self.makeURL(title: title, body: body(model: model, log: Array(entries.suffix(lines))))
            guard let url, url.absoluteString.count > Self.maxURLLength, lines > 0 else { return url }
            lines = max(0, lines - 5)
        }
    }

    private func body(model: AppModel, log: [DiagnosticsLog.Entry]) -> String {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        var body = """
        ### What happened
        \(text.isEmpty ? "_Describe the bug: what you did, what you expected, what happened._" : text)

        ### Device
        - intfy: \(model.appVersion), commit \(model.appCommit)
        - iOS: \(UIDevice.current.systemVersion)
        - Device: \(Self.deviceName)

        ### Setup
        - Servers: \(model.activeServers.count)
        - Silent audio: \(model.audioKeepAliveEnabled ? (model.isAudioPlaying ? "on" : "on, not playing") : "off")
        - Location: \(Self.describe(model.locationStatus))
        - Low Power Mode: \(model.isLowPowerMode ? "on" : "off")
        """
        if !log.isEmpty {
            let lines = log.map { "\(DiagnosticsLog.format($0.date))  \($0.text)" }.joined(separator: "\n")
            body += "\n\n### Diagnostics (last \(log.count) entries)\n```\n\(lines)\n```"
        }
        return body
    }

    private static func makeURL(title: String, body: String) -> URL? {
        // urlQueryAllowed keeps "+", "&" and "=" as-is, but GitHub reads "+" as a space.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=#?")
        func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        let query = ["title": title, "body": body, "labels": "bug"]
            .sorted { $0.key > $1.key }
            .map { "\($0.key)=\(encode($0.value))" }
            .joined(separator: "&")
        return URL(string: "\(newIssueURL)?\(query)")
    }

    private static func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While Using"
        case .notDetermined: "not asked"
        default: "denied"
        }
    }

    // MARK: Device

    /// e.g. "iPhone 15 Pro (iPhone16,1)"; just the identifier for models not in the table.
    static var deviceName: String {
        let id = modelIdentifier
        if let name = modelNames[id] { return "\(name) (\(id))" }
        if ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] != nil { return "\(id) (Simulator)" }
        return id
    }

    /// Hardware identifier such as "iPhone16,1" (the Simulator reports the simulated model).
    static var modelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// iPhones that can run iOS 17. Newer models fall back to the identifier.
    private static let modelNames: [String: String] = [
        "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max", "iPhone11,6": "iPhone XS Max",
        "iPhone11,8": "iPhone XR",
        "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd gen)",
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max", "iPhone14,6": "iPhone SE (3rd gen)",
        "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus", "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus", "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,5": "iPhone 16e",
    ]
}
