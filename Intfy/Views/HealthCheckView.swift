import SwiftUI

struct HealthCheckView: View {
    @Environment(AppModel.self) private var model

    /// Bumped to make every server section re-run its checks.
    @State private var runID = UUID()

    var body: some View {
        List {
            summary

            if model.activeServers.isEmpty {
                Section("Servers") {
                    Text("No servers yet. Add one in Settings.").foregroundStyle(.secondary)
                }
            }
            ForEach(model.activeServers) { server in
                ServerHealthSection(server: server, runID: runID)
            }

            Section {
                LabeledContent("Last Message") {
                    if let date = model.store.messages.first?.date {
                        Text(date, format: .relative(presentation: .named))
                    } else {
                        Text("None yet")
                    }
                }
            }

            Section {
                PermissionRows()
            } header: {
                Text("Permissions")
            } footer: {
                if model.locationStatus == .authorizedWhenInUse && !model.canPromptForLocation {
                    Text("iOS won't ask again. Go to Settings → intfy → Location and choose “Always”.")
                } else if model.localNetworkStatus == .denied {
                    Text("Needed for servers on your LAN. Go to Settings → intfy and turn on Local Network.")
                }
            }

            Section("Background") {
                LabeledContent("Silent Audio") {
                    if !model.audioKeepAliveEnabled {
                        Text("Off")
                    } else if model.isAudioPlaying {
                        GrantedBadge(text: "Playing")
                    } else {
                        WarningBadge(text: "Not playing")
                    }
                }
                LabeledContent("Background App Refresh") {
                    if model.backgroundRefreshStatus == .available {
                        GrantedBadge(text: "On")
                    } else {
                        Button("Off – Open Settings") { model.openSystemSettings() }
                            .foregroundStyle(.orange)
                    }
                }
                LabeledContent("Low Power Mode") {
                    if model.isLowPowerMode {
                        WarningBadge(text: "On")
                    } else {
                        GrantedBadge(text: "Off")
                    }
                }
            }
        }
        .navigationTitle("Health Check")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Run Again", systemImage: "arrow.triangle.2.circlepath") { runID = UUID() }
            }
        }
        .refreshable { runID = UUID() }
    }

    private var summary: some View {
        let issues = model.healthIssues
        return Section {
            HStack(spacing: 14) {
                SettingsIcon(systemName: issues.isEmpty ? "checkmark" : "exclamationmark",
                             color: issues.isEmpty ? .green : .orange, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(issues.isEmpty ? "Everything looks good" : "\(issues.count) \(issues.count == 1 ? "issue" : "issues") found")
                        .font(.headline)
                    Text(issues.isEmpty ? "intfy should receive notifications in the background." : issues.joined(separator: "\n"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Stream state, reachability and topic access for one server, plus its actions.
private struct ServerHealthSection: View {
    @Environment(AppModel.self) private var model
    let server: ServerConfig
    let runID: UUID

    private enum Check: Equatable {
        case idle, running
        case passed(String)
        case failed(String)
    }

    @State private var reachability: Check = .idle
    @State private var topicAccess: Check = .idle
    @State private var testResult: String?
    @State private var isSendingTest = false

    var body: some View {
        Section {
            let state = model.connection(for: server.id)
            LabeledContent("Stream") {
                HStack(spacing: 6) {
                    ConnectionBadge(state: state)
                    Text(state.label).multilineTextAlignment(.trailing)
                }
            }
            checkRow("Server", reachability)
            checkRow("Topic Access", topicAccess)
            Button("Reconnect", systemImage: "arrow.clockwise") { model.reconnect(server) }
            Button {
                Task { await sendTest() }
            } label: {
                HStack {
                    Label("Send Test Notification", systemImage: "paperplane")
                    if isSendingTest { Spacer(); ProgressView() }
                }
            }
            .disabled(isSendingTest)
        } header: {
            Text(server.displayName)
        } footer: {
            if let testResult {
                Text(testResult)
            } else {
                Text("Server checks `/v1/health`. Topic Access checks that the credentials can read \(server.topics.joined(separator: ", ")).")
            }
        }
        .task(id: runID) { await runChecks() }
    }

    private func checkRow(_ title: String, _ check: Check) -> some View {
        LabeledContent(title) {
            switch check {
            case .idle: Text("–")
            case .running: ProgressView()
            case .passed(let text): GrantedBadge(text: text)
            case .failed(let text):
                Text(text).foregroundStyle(.red).multilineTextAlignment(.trailing)
            }
        }
    }

    private func runChecks() async {
        reachability = .running
        topicAccess = .running
        async let health = Result { try await model.checkServerHealth(server) }
        async let access = Result { try await model.checkTopicAccess(server) }

        switch await health {
        case .success(let seconds): reachability = .passed("Healthy · \(Int(seconds * 1000)) ms")
        case .failure(let error): reachability = .failed(error.localizedDescription)
        }
        switch await access {
        case .success: topicAccess = .passed("OK")
        case .failure(let error): topicAccess = .failed(error.localizedDescription)
        }
    }

    private func sendTest() async {
        isSendingTest = true
        defer { isSendingTest = false }
        do {
            try await model.sendTestMessage(to: server)
            testResult = "Sent to “\(server.topics.first ?? "")” – the notification should arrive in a moment."
        } catch {
            testResult = "Error: \(error.localizedDescription)"
        }
    }
}

private extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
