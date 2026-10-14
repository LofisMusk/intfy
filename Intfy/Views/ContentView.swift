import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            MessagesView()
                .tabItem { Label("Messages", systemImage: "bell") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .badge(model.healthIssues.isEmpty ? nil : "!")
        }
    }
}

extension NtfySubscription.State {
    var label: String {
        switch self {
        case .idle: "Disconnected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .retrying(let reason): "Retrying – \(reason)"
        }
    }

    /// Toolbar variant; the full error is shown in Settings.
    var shortLabel: String {
        if case .retrying = self { return "Retrying…" }
        return label
    }

    var color: Color {
        switch self {
        case .idle: .secondary
        case .connecting: .orange
        case .connected: .green
        case .retrying: .red
        }
    }
}

struct ConnectionBadge: View {
    let state: NtfySubscription.State

    var body: some View {
        Circle()
            .fill(state.color)
            .frame(width: 10, height: 10)
            .accessibilityLabel(state.label)
    }
}
