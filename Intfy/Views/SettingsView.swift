import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.servers) { server in
                        NavigationLink { ServerSettingsView(serverID: server.id) } label: {
                            ServerRow(server: server)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { model.servers[$0].id }.forEach(model.deleteServer)
                    }
                    NavigationLink { ServerSettingsView(serverID: nil) } label: {
                        SettingsRow(icon: "plus", color: .green, title: "Add Server")
                    }
                } header: {
                    Text("Servers")
                }

                Section {
                    NavigationLink { HealthCheckView() } label: {
                        let issues = model.healthIssues.count
                        SettingsRow(icon: "stethoscope", color: issues == 0 ? .green : .orange,
                                    title: "Health Check",
                                    value: issues == 0 ? "All good" : "\(issues) \(issues == 1 ? "issue" : "issues")")
                    }
                    NavigationLink { BackgroundSettingsView() } label: {
                        SettingsRow(icon: "moon.zzz.fill", color: .indigo, title: "Background",
                                    value: model.audioKeepAliveEnabled ? "Audio + Location" : "Location only")
                    }
                }

                Section {
                    NavigationLink { DiagnosticsView() } label: {
                        SettingsRow(icon: "waveform.path.ecg", color: .gray, title: "Diagnostics")
                    }
                    NavigationLink { BugReportView() } label: {
                        SettingsRow(icon: "ladybug.fill", color: .red, title: "Report a Bug")
                    }
                    NavigationLink { AboutView() } label: {
                        SettingsRow(icon: "info", color: .intfy, title: "About", value: model.appVersion)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct ServerRow: View {
    @Environment(AppModel.self) private var model
    let server: ServerConfig

    var body: some View {
        let state = model.connection(for: server.id)
        HStack(spacing: 12) {
            SettingsIcon(systemName: "server.rack", color: .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName).lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ConnectionBadge(state: server.isComplete ? state : .idle)
        }
    }

    /// The address when a nickname hides it, plus the topics.
    private var subtitle: String {
        var parts: [String] = []
        if !server.name.isEmpty, let host = server.baseURL?.host() { parts.append(host) }
        parts.append(server.topics.isEmpty ? "No topics" : server.topics.joined(separator: " · "))
        return parts.joined(separator: " — ")
    }
}
