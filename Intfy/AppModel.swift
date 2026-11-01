import BackgroundTasks
import CoreLocation
import Network
import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    static let refreshTaskID = "dev.intfy.refresh"

    private(set) var servers: [ServerConfig]
    private(set) var connections: [UUID: NtfySubscription.State] = [:]
    private(set) var locationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var locationAccuracy: CLAccuracyAuthorization = .reducedAccuracy
    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var localNetworkStatus: LocalNetworkPermission.Status = .unknown
    private(set) var audioKeepAliveEnabled: Bool
    private(set) var isAudioPlaying = false
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var backgroundRefreshStatus: UIBackgroundRefreshStatus = .available
    let store = MessageStore()

    /// One live stream per server.
    @ObservationIgnored private var subscriptions: [UUID: NtfySubscription] = [:]
    @ObservationIgnored private let location = LocationKeepAlive()
    @ObservationIgnored private let notifications = NotificationService()
    @ObservationIgnored private let localNetwork = LocalNetworkPermission()
    @ObservationIgnored private let audio = AudioKeepAlive()
    @ObservationIgnored private let diagnostics = DiagnosticsLog.shared
    @ObservationIgnored private var lastLoggedConnection: [UUID: String] = [:]
    @ObservationIgnored private var lastLocationLog = Date.distantPast
    @ObservationIgnored private var locationUpdatesSinceLog = 0
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var lastPathSignature: String?
    @ObservationIgnored private var lastPoll: [UUID: Date] = [:]
    @ObservationIgnored private var launched = false
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var promptInFlight: PermissionPrompt?

    private enum PermissionPrompt { case notifications, location, localNetwork }

    private static let audioKeepAliveKey = "audioKeepAlive"

    private init() {
        let (servers, migrated) = ServerConfig.loadAll()
        self.servers = servers
        audioKeepAliveEnabled = UserDefaults.standard.object(forKey: Self.audioKeepAliveKey) as? Bool ?? true
        if let migrated {
            store.migrateLegacyCursor(to: migrated.id)
            store.adoptUnassignedMessages(into: migrated.id)
        }
    }

    // MARK: Servers

    /// Servers with an address and at least one topic — the ones we actually subscribe to.
    var activeServers: [ServerConfig] { servers.filter(\.isComplete) }

    func server(with id: UUID?) -> ServerConfig? {
        id.flatMap { id in servers.first { $0.id == id } }
    }

    func connection(for id: UUID) -> NtfySubscription.State { connections[id] ?? .idle }


    func secret(for server: ServerConfig) -> String { Keychain.get(server.secretAccount) ?? "" }

    private func client(for server: ServerConfig) -> NtfyClient {
        NtfyClient(config: server, secret: Keychain.get(server.secretAccount))
    }

    /// Adds a new server or updates an existing one (matched by `id`), then (re)connects it.
    func saveServer(_ server: ServerConfig, secret: String) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            if servers[index].endpointKey != server.endpointKey { store.resetCursor(for: server.id) }
            servers[index] = server
        } else {
            servers.append(server)
        }
        ServerConfig.saveAll(servers)
        Keychain.set(server.authMode == .none ? nil : secret, for: server.secretAccount)
        diagnostics.log("Saved server \(server.displayName)")
        connect(server)
        promptNext()
    }

    func deleteServer(_ id: UUID) {
        guard let server = server(with: id) else { return }
        subscriptions[id]?.stop()
        subscriptions[id] = nil
        connections[id] = nil
        servers.removeAll { $0.id == id }
        ServerConfig.saveAll(servers)
        Keychain.set(nil, for: server.secretAccount)
        store.resetCursor(for: id)
        diagnostics.log("Removed server \(server.displayName)")
    }

    // MARK: Lifecycle

    /// Called from `application(_:didFinishLaunchingWithOptions:)`, which also runs when iOS
    /// relaunches the app in the background for a significant location change.
    func launch() {
        guard !launched else { return }
        launched = true

        location.onStatusChange = { [weak self] status, accuracy in
            guard let self else { return }
            locationStatus = status
            locationAccuracy = accuracy
            if promptInFlight == .location {
                promptInFlight = nil
                promptNext()
            }
        }
        location.onWake = { [weak self] in self?.handleWake() }
        localNetwork.onChange = { [weak self] status in
            guard let self else { return }
            let wasBlocked = localNetworkStatus != .granted
            localNetworkStatus = status
            // Requests made before access was granted failed; don't wait for the backoff.
            if status == .granted && wasBlocked { reconnectDisconnected() }
        }
        locationStatus = location.status
        locationAccuracy = location.accuracy
        location.start()

        audio.onEvent = { [weak self] event in
            guard let self else { return }
            diagnostics.log(event)
            isAudioPlaying = audio.isPlaying
        }
        if audioKeepAliveEnabled { audio.start() }

        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }

        startPathMonitor()
        connectAll()
        scheduleBackgroundRefresh()
    }

    /// The scene is active only while no system alert covers it.
    func becameActive() {
        isActive = true
        diagnostics.log("Moved to foreground")
        backgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        if audioKeepAliveEnabled && !audio.isPlaying { audio.start() }
        locationStatus = location.status
        locationAccuracy = location.accuracy
        Task { await refreshNotificationStatus() }
        // Back to active means the location / local-network alert was answered (or never shown);
        // the notification step clears itself when its request returns.
        if promptInFlight != .notifications { promptInFlight = nil }
        if localNetworkStatus == .denied && promptInFlight == nil { localNetwork.recheck() }
        promptNext()
        ensureConnected()
        // A down server may be sleeping through a long background backoff; try now.
        retryNow()
    }

    func enteredBackground() {
        isActive = false
        store.saveCursors()
        // The Bonjour probe only matters while the user can answer the prompt.
        if localNetworkStatus != .granted { localNetwork.pause() }
        diagnostics.log("Moved to background (audio keep-alive \(audio.isPlaying ? "playing" : "off"), location \(Self.describe(locationStatus)))")
    }

    /// Called from `applicationWillTerminate`.
    func willTerminate() {
        store.saveCursorsIfNeeded()
    }

    func setAudioKeepAlive(_ enabled: Bool) {
        audioKeepAliveEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.audioKeepAliveKey)
        if enabled { audio.start() } else { audio.stop() }
    }

    /// iOS can silently drop a permission alert requested while another one is on screen
    /// (a dropped local-network alert leaves requests failing with "Local network prohibited"),
    /// so permissions are asked strictly one at a time, each only while the app is active:
    /// notifications → location While Using → Always → local network (once a server is set up).
    private func promptNext() {
        guard isActive, promptInFlight == nil else { return }
        if notificationStatus == .notDetermined {
            promptInFlight = .notifications
            Task {
                if await notifications.authorizationStatus() == .notDetermined {
                    await notifications.requestAuthorization()
                }
                await refreshNotificationStatus()
                promptInFlight = nil
                promptNext()
            }
        } else if location.canPrompt {
            promptInFlight = .location
            location.requestAuthorization()
        } else if !activeServers.isEmpty && localNetworkStatus == .unknown {
            promptInFlight = .localNetwork
            localNetwork.check()
        }
    }

    // MARK: Permissions

    func requestLocalNetworkPermission() {
        if localNetworkStatus == .denied {
            openSystemSettings()
        } else if promptInFlight == nil {
            promptInFlight = .localNetwork
            localNetwork.check()
        }
    }

    /// False once iOS won't prompt again — Always can then only be set in the Settings app.
    var canPromptForLocation: Bool {
        _ = locationStatus  // observe status changes
        return location.canPrompt
    }

    func requestLocationPermission() {
        if location.canPrompt {
            guard promptInFlight == nil else { return }
            promptInFlight = .location
            location.requestAuthorization()
        } else {
            openSystemSettings()
        }
    }

    func requestNotificationPermission() async {
        if notificationStatus == .notDetermined {
            await notifications.requestAuthorization()
            await refreshNotificationStatus()
        } else {
            openSystemSettings()
        }
    }

    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    // MARK: Health checks

    func checkServerHealth(_ server: ServerConfig) async throws -> TimeInterval {
        try await client(for: server).health()
    }

    /// A poll that returns (almost) nothing, but fails with 401/403 if the credentials can't read the topics.
    func checkTopicAccess(_ server: ServerConfig) async throws {
        _ = try await client(for: server).poll(since: "1s")
    }

    func reconnect(_ server: ServerConfig) {
        diagnostics.log("Manual reconnect: \(server.displayName)")
        connect(server)
    }

    func sendTestMessage(to server: ServerConfig) async throws {
        guard let topic = server.topics.first else { throw NtfyError.notConfigured }
        try await client(for: server).publish(topic: topic, title: "intfy", message: "Test notification works ✅")
    }

    // MARK: Connection

    private func connect(_ server: ServerConfig) {
        guard server.isComplete else {
            subscriptions[server.id]?.stop()
            return
        }
        subscription(for: server.id).start(client: client(for: server))
    }

    private func connectAll() {
        servers.forEach(connect)
    }

    private func reconnectDisconnected() {
        activeServers.filter { connection(for: $0.id) != .connected }.forEach(connect)
    }

    /// Restarts streams waiting out a retry backoff; leaves connected and connecting ones alone.
    private func retryNow() {
        activeServers.filter { subscriptions[$0.id]?.isRetrying == true }.forEach(connect)
    }

    private func subscription(for id: UUID) -> NtfySubscription {
        if let existing = subscriptions[id] { return existing }
        let subscription = NtfySubscription()
        subscription.onState = { [weak self] state in
            self?.connections[id] = state
            self?.logConnection(state, server: id)
        }
        subscription.onEvent = { [weak self] in self?.handle($0, from: id) }
        subscription.onLog = { [weak self] text in
            guard let self else { return }
            diagnostics.log("\(server(with: id)?.displayName ?? "Server"): \(text)")
        }
        subscription.since = { [weak self] in self?.store.sinceParameter(for: id) }
        // Retrying every 30 s against an unreachable server (e.g. a home server while you are
        // out) keeps waking the radio. In the background back off up to 5 min: a network change
        // and opening the app both reconnect immediately, and messages are caught up via `since`.
        subscription.maxRetryDelay = { [weak self] in self?.isActive == true ? 30 : 5 * 60 }
        subscriptions[id] = subscription
        return subscription
    }

    private func ensureConnected() {
        for server in activeServers {
            let subscription = subscriptions[server.id]
            if subscription == nil || !subscription!.isRunning || subscription!.isStale { connect(server) }
        }
    }

    private func handle(_ event: NtfyMessage, from serverID: UUID) {
        var event = event
        event.serverID = serverID
        if event.time > 0 { store.advanceCursor(for: serverID, to: event.time) }
        guard event.isMessage else { return }
        if store.insertIfNew(event) {
            notifications.post(event, serverName: server(with: serverID)?.displayName)
        }
    }

    /// Location callback: verify the streams are alive, and catch up via a poll where they aren't.
    private func handleWake() {
        locationUpdatesSinceLog += 1
        if Date().timeIntervalSince(lastLocationLog) > 10 * 60 {
            diagnostics.log("Location updates received: \(locationUpdatesSinceLog) since last entry")
            lastLocationLog = Date()
            locationUpdatesSinceLog = 0
        }
        if audioKeepAliveEnabled && !audio.isPlaying { audio.start() }
        ensureConnected()
        for server in activeServers where connection(for: server.id) != .connected {
            if Date().timeIntervalSince(lastPoll[server.id] ?? .distantPast) > 60 {
                Task { await poll(server) }
            }
        }
    }

    /// Catch-up fetch from every server (pull to refresh, background refresh).
    func pollAll() async {
        for server in activeServers { await poll(server) }
    }

    private func poll(_ server: ServerConfig) async {
        lastPoll[server.id] = Date()
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "ntfy-poll")
        defer { UIApplication.shared.endBackgroundTask(taskID) }
        do {
            let since = store.sinceParameter(for: server.id) ?? "5m"
            for message in try await client(for: server).poll(since: since) { handle(message, from: server.id) }
        } catch {
            // The stream's retry loop reports connection errors; a failed poll is just a missed chance.
        }
    }

    private func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            let signature = satisfied ? Self.signature(of: path.availableInterfaces) : "offline"
            Task { @MainActor in self?.pathChanged(signature: signature, satisfied: satisfied) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "dev.intfy.path"))
    }

    /// The interfaces the streams can actually be using. While Wi-Fi or Ethernet is up, the
    /// cellular interface is only a standby that comes and goes with signal strength; counting
    /// it would tear down and re-handshake every healthy stream each time it flaps.
    nonisolated private static func signature(of interfaces: [NWInterface]) -> String {
        let hasLocal = interfaces.contains { $0.type == .wifi || $0.type == .wiredEthernet }
        let relevant = hasLocal ? interfaces.filter { $0.type != .cellular } : interfaces
        return relevant.map(\.name).joined(separator: ",")
    }

    /// Wi-Fi ↔ cellular switches leave the old sockets dangling until timeout; reconnect right away.
    private func pathChanged(signature: String, satisfied: Bool) {
        defer { lastPathSignature = signature }
        guard let previous = lastPathSignature, previous != signature, satisfied else { return }
        diagnostics.log("Network changed (\(previous) → \(signature)), reconnecting")
        connectAll()
    }

    // MARK: Background refresh (extra fallback in case iOS ever suspends the app)

    static func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: .main) { task in
            MainActor.assumeIsolated {
                let model = AppModel.shared
                model.diagnostics.log("Background refresh task ran")
                model.scheduleBackgroundRefresh()
                let work = Task {
                    model.ensureConnected()
                    await model.pollAll()
                    task.setTaskCompleted(success: true)
                }
                task.expirationHandler = { work.cancel() }
            }
        }
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Logs connects and errors, skipping the connecting/retrying churn of a down server.
    private func logConnection(_ state: NtfySubscription.State, server id: UUID) {
        guard state != .connecting else { return }
        let label = state.label
        guard label != lastLoggedConnection[id] else { return }
        lastLoggedConnection[id] = label
        diagnostics.log("\(server(with: id)?.displayName ?? "Server"): \(label)")
    }

    private static func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While Using"
        case .notDetermined: "not asked"
        default: "denied"
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await notifications.authorizationStatus()
    }
}
