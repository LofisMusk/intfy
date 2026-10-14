import CoreLocation

/// Uses background location purely as a keep-alive: while location updates are running with
/// the `location` background mode, iOS does not suspend the app, so the ntfy socket stays open.
/// Coarse accuracy (3 km, reduced accuracy by default) keeps GPS off and battery use low.
/// Significant-change monitoring relaunches the app in the background if iOS kills it.
@MainActor
final class LocationKeepAlive: NSObject, CLLocationManagerDelegate {
    var onStatusChange: (CLAuthorizationStatus, CLAccuracyAuthorization) -> Void = { _, _ in }
    /// Called on every location callback — a chance to check the connection health.
    var onWake: () -> Void = {}

    private let manager = CLLocationManager()
    private var isUpdating = false

    private static let askedAlwaysKey = "askedAlwaysUpgrade"
    private var askedAlways: Bool {
        get { UserDefaults.standard.bool(forKey: Self.askedAlwaysKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.askedAlwaysKey) }
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .other
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }
    var accuracy: CLAccuracyAuthorization { manager.accuracyAuthorization }

    /// Whether iOS will still show a permission prompt; otherwise only the Settings app can change it.
    var canPrompt: Bool { status == .notDetermined || (status == .authorizedWhenInUse && !askedAlways) }

    /// Two-step flow, one step per call (AppModel calls again once the first alert is answered).
    /// Asking for Always straight from .notDetermined only offers "While Using" and grants a
    /// provisional Always whose upgrade prompt iOS defers indefinitely. Asking for When In Use
    /// first and then for Always shows "Change to Always Allow" right away.
    func requestAuthorization() {
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            requestAlwaysUpgrade()
        default:
            break
        }
    }

    /// iOS shows the upgrade prompt at most once per install, and only while the app is in the foreground.
    private func requestAlwaysUpgrade() {
        guard status == .authorizedWhenInUse, !askedAlways else { return }
        askedAlways = true
        manager.requestAlwaysAuthorization()
    }

    func start() {
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = false
        if !isUpdating {
            manager.startUpdatingLocation()
            isUpdating = true
        }
        if status == .authorizedAlways {
            manager.startMonitoringSignificantLocationChanges()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            onStatusChange(manager.authorizationStatus, manager.accuracyAuthorization)
            start()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { onWake() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorLocationUnknown etc. are transient; updates keep running.
    }
}
