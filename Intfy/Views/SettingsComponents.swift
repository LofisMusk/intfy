import SwiftUI

extension Color {
    /// The app icon's teal.
    static let intfy = Color(red: 0.16, green: 0.50, blue: 0.53)
}

/// Rounded, colored square icon like the ones in the iOS Settings app.
struct SettingsIcon: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

/// A category row on the Settings root: icon, title, and a short trailing value.
struct SettingsRow: View {
    let icon: String
    let color: Color
    let title: String
    var value: String?

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemName: icon, color: color)
            Text(title)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Green "✓ text" for a passing check. A plain HStack rather than `Label`: inside
/// `LabeledContent` in a `Form`, iOS 26 lays a Label out as a separate block, which left
/// tall empty gaps under the row.
struct GrantedBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
            Text(text)
        }
        .foregroundStyle(.green)
    }
}

/// Orange "⚠ text" for a check that needs attention but isn't fatal.
struct WarningBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
        }
        .foregroundStyle(.orange)
    }
}

/// Permission rows shared by Health Check and Background, each with its fix-it action.
struct PermissionRows: View {
    @Environment(AppModel.self) private var model
    var locationOnly = false

    var body: some View {
        if !locationOnly { notificationsRow }
        locationRows
        if !locationOnly { localNetworkRow }
    }

    private var notificationsRow: some View {
        LabeledContent("Notifications") {
            switch model.notificationStatus {
            case .authorized, .provisional:
                GrantedBadge(text: "On")
            case .notDetermined:
                Button("Allow") { Task { await model.requestNotificationPermission() } }
            default:
                Button("Off – Open Settings") { model.openSystemSettings() }
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder private var locationRows: some View {
        LabeledContent("Location") {
            switch model.locationStatus {
            case .authorizedAlways:
                GrantedBadge(text: "Always")
            case .authorizedWhenInUse:
                Button(model.canPromptForLocation ? "While Using → Allow Always" : "While Using – Open Settings") {
                    model.requestLocationPermission()
                }
                .foregroundStyle(.orange)
            case .notDetermined:
                Button("Allow") { model.requestLocationPermission() }
            default:
                Button("Denied – Open Settings") { model.openSystemSettings() }
                    .foregroundStyle(.red)
            }
        }

        LabeledContent("Accuracy") {
            if model.locationAccuracy == .reducedAccuracy {
                GrantedBadge(text: "Approximate")
            } else {
                Button("Precise – approximate is enough") { model.openSystemSettings() }
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var localNetworkRow: some View {
        LabeledContent("Local Network") {
            switch model.localNetworkStatus {
            case .granted:
                GrantedBadge(text: "Allowed")
            case .unknown:
                Button("Allow") { model.requestLocalNetworkPermission() }
            case .denied:
                Button("Blocked – Open Settings") { model.openSystemSettings() }
                    .foregroundStyle(.red)
            }
        }
    }
}

extension AppModel {
    /// Everything that currently stands in the way of reliable background delivery.
    var healthIssues: [String] {
        var issues: [String] = []
        if activeServers.isEmpty {
            issues.append("No server configured")
        }
        for server in activeServers {
            if case .retrying = connection(for: server.id) {
                issues.append("\(server.displayName): not connected")
            }
        }
        if notificationStatus != .authorized && notificationStatus != .provisional {
            issues.append("Notifications are not allowed")
        }
        if locationStatus != .authorizedAlways { issues.append("Location is not set to Always") }
        if localNetworkStatus == .denied { issues.append("Local Network access is blocked") }
        if audioKeepAliveEnabled && !isAudioPlaying { issues.append("Silent audio keep-alive is not playing") }
        if isLowPowerMode { issues.append("Low Power Mode is on") }
        if backgroundRefreshStatus != .available { issues.append("Background App Refresh is off") }
        return issues
    }

    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var appCommit: String {
        let commit = Bundle.main.infoDictionary?["IntfyCommit"] as? String
        return commit?.isEmpty == false ? commit! : "dev"
    }
}
