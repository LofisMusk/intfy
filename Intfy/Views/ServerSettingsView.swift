import SwiftUI

/// Adds a server (`serverID == nil`) or edits an existing one.
struct ServerSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let serverID: UUID?

    @State private var id = UUID()
    @State private var name = ""
    @State private var host = ""
    @State private var port = ""
    @State private var useTLS = false
    @State private var topics = ""
    @State private var authMode: AuthMode = .none
    @State private var username = ""
    @State private var secret = ""
    @State private var validationError: String?
    @State private var didSave = false
    @State private var loaded = false
    @State private var confirmDelete = false

    private var existing: ServerConfig? { model.server(with: serverID) }

    var body: some View {
        Form {
            Section {
                TextField("e.g. Home, VPS", text: $name)
            } header: {
                Text("Name")
            } footer: {
                Text("Optional. Shown in notifications and the app instead of the address.")
            }

            Section {
                TextField("IP address or host, e.g. 192.168.1.10", text: $host)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Port (default \(useTLS ? 443 : 80))", text: $port)
                    .keyboardType(.numberPad)
                Toggle("HTTPS", isOn: $useTLS)
            } header: {
                Text("Address")
            } footer: {
                if let url = draft?.baseURL { Text(url.absoluteString) }
            }

            Section {
                TextField("e.g. alerts, backup, homelab", text: $topics)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Topics")
            } footer: {
                Text("Comma-separated. Allowed characters: letters, digits, - and _.")
            }

            Section("Authentication") {
                Picker("Method", selection: $authMode) {
                    ForEach(AuthMode.allCases) { Text($0.label).tag($0) }
                }
                switch authMode {
                case .none:
                    EmptyView()
                case .token:
                    SecureField("Token (tk_…)", text: $secret)
                case .basic:
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $secret)
                }
            }

            Section {
                Button(action: save) {
                    Text(existing == nil ? "Add Server" : "Save & Connect").bold().frame(maxWidth: .infinity)
                }
                .disabled(!hasChanges)
            } footer: {
                if let validationError {
                    Text(validationError).foregroundStyle(.red)
                } else if didSave && !hasChanges {
                    Text("Saved. Check the connection in Health Check.")
                }
            }

            if existing != nil {
                Section {
                    Button("Remove Server", role: .destructive) { confirmDelete = true }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(existing?.displayName ?? "New Server")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove \(existing?.displayName ?? "server")?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Remove Server", role: .destructive) {
                if let serverID { model.deleteServer(serverID) }
                dismiss()
            }
        } message: {
            Text("intfy stops receiving its notifications. Messages already received stay in the list.")
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            loadDraft()
        }
        .onChange(of: [name, host, port, topics, username, secret]) { didSave = false }
    }

    private var draft: ServerConfig? {
        var config = ServerConfig()
        config.id = id
        config.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        config.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = port.trimmingCharacters(in: .whitespaces)
        if !trimmedPort.isEmpty {
            guard let value = Int(trimmedPort), (1...65535).contains(value) else { return nil }
            config.port = value
        }
        config.useTLS = useTLS
        config.topics = ServerConfig.parseTopics(topics)
        config.authMode = authMode
        config.username = username.trimmingCharacters(in: .whitespaces)
        return config
    }

    /// A draft that doesn't parse counts as changed, so Save can explain what's wrong.
    private var hasChanges: Bool {
        guard let existing else { return !host.isEmpty }
        guard let draft else { return true }
        return draft != existing || (authMode != .none && secret != model.secret(for: existing))
    }

    private func loadDraft() {
        guard let server = existing else { return }
        id = server.id
        name = server.name
        host = server.host
        port = server.port.map(String.init) ?? ""
        useTLS = server.useTLS
        topics = server.topics.joined(separator: ", ")
        authMode = server.authMode
        username = server.username
        secret = model.secret(for: server)
    }

    private func save() {
        guard let config = draft else {
            validationError = "Invalid port (1–65535)."
            return
        }
        guard config.baseURL != nil else {
            validationError = "Enter the server's IP address or hostname."
            return
        }
        guard !config.topics.isEmpty else {
            validationError = "Enter at least one topic."
            return
        }
        if let bad = config.topics.first(where: { !ServerConfig.isValidTopic($0) }) {
            validationError = "Invalid topic: “\(bad)”."
            return
        }
        validationError = nil
        let isNew = existing == nil
        model.saveServer(config, secret: secret)  // also asks for any missing permissions, one at a time
        if isNew { dismiss() } else { didSave = true }
    }
}
