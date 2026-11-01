import Foundation
import Network

/// Triggers and observes the Local Network privacy permission.
///
/// iOS has no API for this permission. It prompts the first time an app touches the LAN,
/// but a plain HTTP request fired while another system alert is on screen can fail with
/// "Local network prohibited" without ever showing the prompt. Advertising and browsing a
/// Bonjour service (declared in `NSBonjourServices`) reliably shows it, and doubles as a
/// status check: seeing our own service means access was granted.
@MainActor
final class LocalNetworkPermission {
    enum Status { case unknown, granted, denied }

    var onChange: (Status) -> Void = { _ in }
    private(set) var status: Status = .unknown {
        didSet { if status != oldValue { onChange(status) } }
    }

    static let serviceType = "_intfy._tcp"

    private var listener: NWListener?
    private var browser: NWBrowser?

    /// Shows the prompt if undecided; otherwise just refreshes `status`.
    /// The probe stays up while undecided/denied, so an Allow tap (or a later change in
    /// Settings while the probe runs) flips the status to `.granted`.
    func check() {
        guard status != .granted, browser == nil else { return }

        let listener = try? NWListener(using: .tcp)
        listener?.service = NWListener.Service(name: "intfy-\(UUID().uuidString.prefix(8))", type: Self.serviceType)
        listener?.newConnectionHandler = { $0.cancel() }
        listener?.start(queue: .main)
        self.listener = listener

        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                if case .waiting(let error) = state, case .dns(let code) = error,
                   code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) {
                    self?.status = .denied
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                guard !results.isEmpty else { return }
                self?.status = .granted
                self?.stop()
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    /// Restart the probe, e.g. after returning from the Settings app.
    func recheck() {
        guard status != .granted else { return }
        stop()
        check()
    }

    /// Stops the probe (in the background); `check()` or `recheck()` starts it again.
    func pause() {
        stop()
    }

    private func stop() {
        browser?.cancel()
        browser = nil
        listener?.cancel()
        listener = nil
    }
}
