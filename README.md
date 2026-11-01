# intfy

An iOS app for your own [ntfy](https://ntfy.sh) server. Messages show up as normal iOS notifications.

No Apple push (APNs), no ntfy.sh relay, no Apple servers. Your server talks straight to your phone.

## Install

Add this source in **SideStore**, **AltStore**, **LiveContainer** or **Feather**:

```
https://lofismusk.github.io/intfy/source.json
```

Or open [lofismusk.github.io/intfy](https://lofismusk.github.io/intfy/) on your iPhone and tap *Add to SideStore*. New builds then show up as updates in the app.

Prefer a file? Grab the latest `.ipa` from [Releases](https://github.com/LofisMusk/intfy/releases/latest) and sideload it with any tool (SideStore, AltStore, Sideloadly).

Needs iOS 17 or newer. A free Apple ID is enough.

## Setup

1. Open intfy and allow **notifications**.
2. Go to **Settings → Add Server** and fill in:
   - **Host:** IP or hostname, e.g. `192.168.1.10`
   - **Port:** empty means 80 (or 443 with HTTPS)
   - **Topics:** comma-separated, e.g. `alerts, backup`
   - **Auth:** none, a token (`tk_…`) or username + password
   - **Name:** optional nickname, e.g. `Home`
3. Tap **Save & Connect**.
4. Allow **location**: first *While Using*, then *Change to Always Allow*. Approximate location is fine; leave *Precise* off.
5. Allow **Local Network** if your server is on your home network.
6. Go to **Settings → Health Check → Send Test Notification**. If it pops up, you're done.

You can add as many servers as you want.

## How it works

iOS freezes apps a few seconds after you leave them. Most apps get around that with Apple push. intfy doesn't use push, so it stays awake instead:

- **Silent audio.** The app plays silence on a loop. While audio is playing, iOS doesn't freeze the app. It mixes with your music and shows no player controls. You can turn it off in *Settings → Background*.
- **Background location.** Approximate location only, no GPS. It's a second keep-alive, and it lets iOS restart the app if it gets killed. The location itself is ignored; it's never saved or sent anywhere.
- **One open connection per server** to `GET /<topics>/json`. ntfy sends one JSON line per event, and every message becomes a local notification.
- **Nothing gets lost.** The app remembers the server time of the last event it saw. After a reconnect it asks for everything `since` then, and drops duplicates.

If the app gets frozen anyway, it catches up when it wakes: after a network change, on a location update, or on iOS background refresh (roughly every 15 min). Messages stay on your server for 12 h by default (`cache-duration`), so they arrive late but don't disappear.

ntfy priorities map to iOS like this: 1–2 silent, 3 normal, 4–5 time-sensitive.

## Battery

Staying awake costs battery, and silent audio costs the most. The app keeps all the keep-alives (that's what makes it reliable) but avoids every other wake-up.

The biggest thing you can do is on the server. ntfy sends a keepalive every 45 s by default, and each one wakes the phone's radio. Raise it in `server.yml`:

```yaml
keepalive-interval: "2m"
```

The app picks up the new interval by itself. Keep it below your reverse proxy's timeout: nginx `proxy_read_timeout` is 60 s by default, Cloudflare cuts idle connections at about 100 s. Going above 3 min can also run into mobile carriers dropping idle connections.

To measure: while unplugged, *Settings → Diagnostics* logs battery drain in %/h every 5 %.

## Privacy

- The app only talks to the servers you add. No analytics, no tracking, no third-party code.
- Tokens and passwords are stored in the Keychain on this device only.
- Plain HTTP is allowed so LAN servers work. Over the internet, use HTTPS or a VPN like Tailscale or WireGuard.

## Troubleshooting

- **Unauthorized (401/403):** wrong token or password, or no read access to the topic.
- **Not found (404):** wrong host or port, or a reverse proxy with a path prefix.
- **Can't connect on the LAN:** allow *Local Network* in *iOS Settings → intfy*. The server must listen on `0.0.0.0`, not `127.0.0.1`.
- **Notifications stop in the background:** open *Settings → Diagnostics*. "Not running for N min" means iOS froze the app; "ended without notice" means it was killed or crashed. Keep silent audio on, location on *Always*, and avoid Low Power Mode.
- **Notifications stop after swiping the app away:** open it once and it reconnects.
- **High battery use:** see [Battery](#battery). Lots of "Network changed" or reconnect lines in Diagnostics point to a flaky network or proxy.

Test your server from a computer:

```sh
curl -s http://192.168.1.10/alerts/json      # prints {"event":"open",...} and then keepalives
curl -d "hello" http://192.168.1.10/alerts   # sends a test message
```

## Build

You need a Mac with Xcode 16 or newer. No packages to install.

```sh
git clone https://github.com/LofisMusk/intfy.git
cd intfy
./scripts/build-ipa.sh      # → build/intfy-<commit>.ipa (unsigned)
```

To run it from Xcode on your own phone, set up signing once:

```sh
cp Config/Signing.xcconfig.example Config/Signing.xcconfig
# set DEVELOPMENT_TEAM and a unique PRODUCT_BUNDLE_IDENTIFIER
```

That file is gitignored. Don't pick a team in Xcode's *Signing & Capabilities* tab; that writes it into the project file, which is committed.

### CI and releases

Every push builds an IPA in GitHub Actions (download it from the run's artifacts). A push to `main` also:

1. creates a release `intfy-<commit>` with the IPA,
2. updates the source on GitHub Pages (`scripts/make-source.py`).

The version is `1.0.<number of commits>`, so every build is newer than the last and sideloading apps see it as an update. Nobody tags anything by hand.

One-time repo setting for Pages: *Settings → Pages → Source: GitHub Actions*.

## Code map

```
Intfy/
  IntfyApp.swift            app entry; startup happens here (also on background relaunch)
  AppModel.swift            wires everything together, holds the UI state
  NtfySubscription.swift    the live connection: reconnects, backoff, keepalive timeout
  NtfyClient.swift          builds requests: stream, poll, publish, auth
  NtfyMessage.swift         ntfy event model, notification text, tag → emoji
  MessageStore.swift        message history, duplicate check, "since" cursor
  AudioKeepAlive.swift      silent audio loop
  LocationKeepAlive.swift   background location keep-alive
  NotificationService.swift local notifications
  DiagnosticsLog.swift      on-device log: heartbeat, app lifecycle, battery
  BugReport.swift           prefilled GitHub issue (versions, device model)
  ServerConfig.swift        server list + Keychain
  Views/                    SwiftUI screens
Config/Info.plist           permissions text, background modes
scripts/                    build-ipa.sh, make-source.py, make-icon.swift
```

## Contributing

Found a bug? In the app, tap **Settings → Report a Bug**. It opens a GitHub issue with your versions and device already filled in.

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE)
