# intfy

intfy is a sideloadable iOS client for **self-hosted [ntfy](https://ntfy.sh) servers**. It shows ntfy messages as **local notifications**, so it does not need APNs, the ntfy.sh upstream server or any connection to Apple's servers. Your server talks only to your phone.

- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Building](#building)
- [Installing (sideloading)](#installing-sideloading)
- [Setup](#setup)
- [Using the app](#using-the-app)
- [Architecture](#architecture)
- [ntfy protocol details](#ntfy-protocol-details)
- [Privacy & security](#privacy--security)
- [Battery](#battery)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)
- [Testing without a real server](#testing-without-a-real-server)
- [Contributing](#contributing)
- [License](#license)

---

## How it works

iOS normally suspends an app a few seconds after it goes to the background. The official ntfy app gets around this with APNs push, which needs Apple's servers and, for self-hosted setups, the ntfy.sh upstream relay. intfy uses a different approach:

1. **Background location as a keep-alive.** The app requests the **"Always"** location permission with **approximate (reduced) accuracy** as the default. It runs continuous location updates with the `location` background mode, 3 km desired accuracy and automatic pausing disabled. While those updates run, iOS keeps the process alive. The location data itself is ignored.
   - **Silent audio keep-alive** (on by default; toggle in *Settings → Background*). In practice, iOS does not always keep an app alive on coarse location alone. The app therefore also loops one second of silent PCM with the `audio` background mode. The audio session uses `.playback` with `.mixWithOthers`, so it never pauses your music and shows no Now Playing controls. After an interruption (a call, Siri or an alarm), playback resumes on its own. It is also restarted on every location wake-up and every return to the foreground. Location remains in use to relaunch the app after iOS kills it.
2. **A persistent connection to ntfy.** The app keeps one long-lived HTTP stream open to `GET http://<host>:<port>/<topic1,topic2>/json`. ntfy sends one JSON object per line.
3. **Local notifications.** Each `message` event becomes a `UNNotificationRequest` with no trigger, which iOS delivers immediately. No push token or APNs is involved.
4. **Nothing gets lost.** Every event the server sends carries the server's time, and the app stores the latest one as a cursor. On reconnect it asks for `since=<cursor>`, and duplicates are dropped by message ID.

If iOS suspends or kills the app anyway, these fallbacks take over:

| Mechanism | What it does |
|---|---|
| Significant-location-change monitoring | iOS relaunches a terminated app in the background; `AppDelegate` reconnects immediately. |
| Wake-up poll | On each location callback, if the stream is down, the app runs a one-shot `poll=1&since=…` fetch (throttled to once per 60 s). |
| `BGAppRefreshTask` (`dev.intfy.refresh`) | Opportunistic refresh, earliest every 15 min, scheduled by iOS. |
| `NWPathMonitor` | Reconnects immediately when the network changes (Wi-Fi ↔ cellular) instead of waiting for the dead socket to time out. The cellular interface is ignored while Wi-Fi or Ethernet is up, so a flapping mobile signal doesn't tear down healthy streams. |
| Stale-socket detection | No data for two keepalive intervals plus 15 s (at least 100 s) means a dead connection, so the app reconnects. The interval is learned from the stream; see [Battery](#battery). |

## Requirements

- **To run:** iPhone or iPad with iOS 17 or later.
- **To build:** a Mac with Xcode 16 or later. The project uses the Xcode 16 synchronized-folder format, so there is no XcodeGen or CocoaPods.
- **Server:** any ntfy server reachable from the phone, such as one on your LAN or over Tailscale or WireGuard.

## Building

Build an unsigned IPA from the command line:

```sh
./scripts/build-ipa.sh            # → build/intfy-<short commit hash>.ipa
CONFIGURATION=Debug ./scripts/build-ipa.sh
```

Builds are versioned by commit. Nobody tags by hand: CI creates a release (and its tag) for each build on `main`.

### CI builds

The GitHub Actions workflow `.github/workflows/build-ipa.yml` builds the IPA on every push that changes the app, meaning anything under `Intfy/`, `Intfy.xcodeproj/`, `Config/`, `scripts/build-ipa.sh` or the workflow itself. You can also start it by hand under *Actions → Build IPA → Run workflow*.

Each run uploads the build as an **artifact** named `intfy-<short hash>`. GitHub delivers artifacts as a zip that contains the `.ipa` and keeps them for 90 days by default.

On `main`, the workflow also publishes a **GitHub release** named `intfy-<short hash>` with the `.ipa` attached directly (no zip). Its title and notes come from the commit message, and the newest one is marked *Latest*. Pushes to other branches only produce artifacts. Re-running the workflow for the same commit replaces the release asset instead of creating a duplicate.

Or build and run from Xcode on a connected device. Signing settings live in a personal, gitignored file, so everyone signs with their own Apple ID:

```sh
cp Config/Signing.xcconfig.example Config/Signing.xcconfig
# edit: DEVELOPMENT_TEAM = <your Team ID>, PRODUCT_BUNDLE_IDENTIFIER = <unique ID, e.g. com.yourname.intfy>
```

Set the team there rather than in Xcode's *Signing & Capabilities* tab: picking a team in the UI writes it into `project.pbxproj`, which is committed. The unsigned IPA build (`build-ipa.sh`) does not need this file.

The app icon is generated from code:

```sh
swift scripts/make-icon.swift     # → Intfy/Assets.xcassets/AppIcon.appiconset/icon-1024.png
```

## Installing (sideloading)

Download the newest `intfy-<hash>.ipa` from [Releases](https://github.com/LofisMusk/intfy/releases/latest), or build it yourself as described above.

The IPA is unsigned. Any of these tools will sign it with your Apple ID:

- **AltStore / SideStore:** open `intfy-<hash>.ipa` from the Files app, or use *My Apps → +*.
- **Sideloadly:** drag in the IPA and enter your Apple ID.
- **Xcode:** build and run directly. With a free account, the app expires after 7 days.

The app needs no special entitlements. The `location` and `fetch` background modes are plain `Info.plist` keys, so it works with free developer accounts.

## Setup

1. Launch intfy and allow **notifications**.
2. Open **Settings → Add Server** and fill in:
   - **Name:** optional nickname such as `Home`. It is shown in notifications and in the app instead of the address, which helps when you connect by IP.
   - **Host:** an IP address or hostname, e.g. `192.168.1.10`. Pasted values like `http://host:8080/` or `[fd00::1]` also work.
   - **Port:** defaults to 80, or 443 with HTTPS.
   - **HTTPS:** enable it if your server uses TLS.
   - **Topics:** comma-separated, e.g. `alerts, backup, homelab`. Allowed characters are `A–Z a–z 0–9 - _`, up to 64 each.
   - **Authentication:** none, an access token (`tk_…`, sent as `Bearer`), or a username and password (sent as `Basic`).
3. Tap **Save & Connect**. The status should change to *Connected*.
4. Grant location **Always**. The app asks in two steps: first choose **Allow While Using App**, and iOS immediately follows up with **Change to Always Allow**. iOS shows that second prompt only once per install; if you dismissed it, set it in *Settings → intfy → Location → Always*.
5. Leave **Precise Location** off, because approximate is enough.
   - **Local Network:** after you save a server, the app asks for local network access (needed for LAN addresses such as `192.168.x.x`). The app asks for one permission at a time, because iOS can silently drop an alert requested while another one is on screen. If you denied it, turn it on in *Settings → intfy → Local Network*.
6. Open **Settings → Health Check** and tap **Send Test Notification**. This publishes a message to your first topic, so it tests the whole path from server to stream to notification.

The Settings tab is grouped like the iOS Settings app:

| Page | What's there |
|---|---|
| **Servers** | One row per server, showing its name, address, topics and a status dot. Tap a row to edit it, swipe to remove it. **Add Server** adds another one. Each server has its name, address, port, HTTPS, topics and authentication. |
| **Health Check** | For each server: stream state, a server check (`/v1/health` with latency), a topic-access check (catches wrong credentials), the last message, **Reconnect**, **Send Test Notification**, every permission, and background factors (silent audio, Background App Refresh, Low Power Mode). |
| **Background** | **Silent Audio Keep-Alive** toggle, location keep-alive status and tips |
| **Diagnostics** | Heartbeat and lifecycle log (see [Troubleshooting](#troubleshooting)) |
| **About** | Version and the commit the build came from |

Anything that is not green links straight to the system prompt or to the Settings app. A red `!` badge on the Settings tab means Health Check found an issue.

## Using the app

- **Messages tab:** the last 300 messages, newest first, stored on the device.
  - Tap a message to open its `click` URL.
  - Long-press to copy the text or open an attachment.
  - Swipe to delete, or pull to refresh, which runs a poll.
- **Notifications:**
  - The header reads `<service> | <topic> | <server>`, e.g. `✅ Proxmox | backup | Home`. *Service* is the message `title`, which the sending service sets. *Server* is the server's nickname, or its host if it has none. Missing parts are left out, e.g. `deploy | 192.168.0.107`. Emoji from known tags such as `warning` → ⚠️ or `white_check_mark` → ✅ go in front.
  - Notifications are grouped per server and topic.
  - You can add any number of servers. Each one has its own stream, `since` cursor and credentials.
  - Tapping a notification opens its `click` URL.

Priority mapping:

| ntfy priority | iOS behaviour |
|---|---|
| 1 (min), 2 (low) | `passive`: silent, appears in Notification Center only |
| 3 (default) | `active`: banner and sound |
| 4 (high), 5 (max) | `timeSensitive`: banner and sound. Without the time-sensitive entitlement, iOS treats it as `active`. |

> **Don't swipe intfy away in the app switcher.** After a force-quit, iOS may not wake the app again until you open it.

## Architecture

```
Intfy/
├── IntfyApp.swift            App entry + AppDelegate (startup happens here, not in a view)
├── AppModel.swift            Orchestrator: wires everything, owns observable UI state
├── NtfySubscription.swift    Long-lived stream, reconnect loop with backoff
├── NtfyClient.swift          Stateless request builder: stream URL, poll, publish, auth
├── NtfyMessage.swift         Event model + notification formatting + tag→emoji map
├── MessageStore.swift        Message history, seen-ID dedup, `since` cursor (persisted)
├── LocationKeepAlive.swift   CLLocationManager used purely to keep the process alive
├── AudioKeepAlive.swift      Looping silent audio (second keep-alive)
├── DiagnosticsLog.swift      Heartbeat + lifecycle event log (Settings → Diagnostics)
├── LocalNetworkPermission.swift  Bonjour probe that triggers/observes Local Network access
├── NotificationService.swift Local notifications + UNUserNotificationCenterDelegate
├── ServerConfig.swift        Server list (UserDefaults) + legacy migration + Keychain helper
└── Views/                    SwiftUI: Messages, Settings root + Server / Health Check /
                              Background / Diagnostics / About pages, shared components
Config/Info.plist             Permission strings, background modes, ATS, BGTask IDs
scripts/                      build-ipa.sh, make-icon.swift
.github/workflows/            build-ipa.yml (CI: IPA per commit)
```

### Startup

`AppDelegate.application(_:didFinishLaunchingWithOptions:)` registers the background task and calls `AppModel.shared.launch()`. Everything starts here rather than in a SwiftUI view, because a background relaunch (after a significant location change) creates no scene. `launch()` does the following:

1. Hooks up the subscription, location and network callbacks.
2. Starts location updates, if location permission has already been granted.
3. Starts `NWPathMonitor`.
4. Opens the ntfy stream, if the configuration is complete.
5. Schedules a `BGAppRefreshTask`.
6. Asks for permissions one at a time: first notifications, then location **While Using**. As soon as that is granted, `LocationKeepAlive` asks for **Always**. Requesting Always directly from the undecided state would only give a provisional Always, and iOS would postpone the upgrade prompt indefinitely.

When the app returns to the foreground, `becameActive()` refreshes the permission status, asks for the Always upgrade if it has not been asked yet, and reconnects if the stream is stale.

### Message flow

```
ntfy server ──HTTP stream──▶ NtfySubscription ──event──▶ AppModel.handle
                                                            │
                         every event: store.advanceCursor(event.time)
                         message only: store.insertIfNew → NotificationService.post
```

`NtfySubscription.run()` loops until cancelled:

1. Builds the stream URL with `since=` taken from the store.
2. Calls `URLSession.bytes(for:)` and reads `bytes.lines`.
3. Decodes each line and passes it to `onEvent`.

Each connection attempt gets its own `URLSession` whose request and idle timeout is `max(100 s, 2 × keepalive + 15 s)`. The keepalive interval starts at ntfy's default of 45 s and is then learned from the time between `open`/`keepalive` events. If a connected stream times out without a single keepalive, the estimate is doubled for the next attempt (capped at 15 min), so a server with a longer `keepalive-interval` is picked up after one or two reconnects. Changes are logged in Diagnostics.

When the stream errors or closes, the loop waits and retries with exponential backoff from 1 s up to 30 s in the foreground and up to 5 min in the background. A successful connection resets the backoff. Opening the app and any network change reconnect immediately, whatever the backoff.

### State & persistence

| Data | Where | Notes |
|---|---|---|
| `[ServerConfig]` | `UserDefaults` (`servers`, JSON) | Per server: id, nickname, host, port, TLS, topics, auth mode, username. A pre-multi-server `serverConfig` is migrated automatically. |
| Token / password | Keychain (`dev.intfy.credentials`, one item per server id) | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so it stays readable in the background while the phone is locked |
| Message history | `Application Support/messages.json` | Capped at 300; file protection `completeUntilFirstUserAuthentication` |
| Seen message IDs | `UserDefaults` (`seenMessageIDs`) | Capped at 2000; prevents duplicate notifications |
| `since` cursors | `UserDefaults` (`sinceCursors`, keyed by server id) | Server Unix time; reset when that server's host, port or topics change. Written at most every 5 min (keepalives advance it constantly), on every new message, when going to the background and on termination. A slightly older cursor after a crash only means re-fetching messages that are then dropped as duplicates. |

## ntfy protocol details

intfy uses only standard ntfy endpoints and needs no server-side changes.

| Purpose | Request |
|---|---|
| Live stream | `GET /<topics>/json[?since=<unix>]`: newline-delimited JSON, kept open |
| Catch-up poll | `GET /<topics>/json?poll=1&since=<unix>`: returns cached messages and closes |
| Test publish | `POST /` with JSON `{"topic","title","message","tags"}` |

**Events.** The app handles `open`, `keepalive` and `message`; other event types are ignored. All of them advance the cursor.

**Cursor.** The cursor is the **server's** clock (the `time` field), so clock drift on the phone doesn't matter. The app sends `since=<cursor − 1>` so the overlap covers messages published in the same second; the ID dedup removes the duplicates. If no cursor exists yet, the fallback poll uses `since=5m`.

**Message fields.** The app reads `id`, `time`, `event`, `topic`, `message`, `title`, `priority`, `tags`, `click` and `attachment` (`name`, `url`, `type`). Attachments appear as `📎 name` in the notification body; they are not downloaded.

**Authentication.** The app sends `Authorization: Bearer <token>` or `Authorization: Basic base64(user:pass)` on every request.

**Message cache.** ntfy keeps messages for 12 h by default (`cache-duration`). If the phone is offline longer than that, older messages can't be recovered. Raise `cache-duration` on the server if you need a longer window.

## Privacy & security

- **Location** is requested only to keep the process alive. Coordinates are never read, stored or sent. Accuracy is 3 km and reduced accuracy is the default (`NSLocationDefaultAccuracyReduced`), so the GPS is never turned on.
- **Network:** the app connects only to the server you configure. There is no analytics or third-party SDK, and APNs is not used.
- **Plain HTTP:** connections to any host are allowed (`NSAllowsArbitraryLoads`). `NSAllowsLocalNetworking` is deliberately not set: when present, iOS ignores `NSAllowsArbitraryLoads` and allows plain HTTP only to IP addresses, `.local` names and unqualified hostnames, which breaks hosts like `ntfy.home`. Over the internet, use **HTTPS or a VPN** (Tailscale or WireGuard); otherwise your messages and credentials travel unencrypted.
- **Credentials** are stored in the Keychain as device-only items: they are never synced to iCloud and never moved to another device when you restore a backup.

## Battery

The keep-alives are what make delivery reliable, and they cost battery. The app keeps all of them and avoids waking the phone for anything else:

| What | Why it matters |
|---|---|
| Learned keepalive interval | Every keepalive wakes the radio. On cellular, each wake keeps the modem in its high-power state for several seconds. The app follows whatever interval the server uses, so you can raise it (see below). |
| Background retry backoff up to 5 min | A server that can't be reached (a home server while you are out, an outage) no longer means a connection attempt every 30 s all day. |
| Cellular ignored while on Wi-Fi | A weak mobile signal makes the cellular interface come and go; this used to reconnect every stream each time. |
| Fewer disk writes and timer wake-ups | The `since` cursor is no longer written on every keepalive, the diagnostics heartbeat runs every 60 s with timer tolerance, and the Local Network probe stops in the background. |

**Biggest lever: the server's keepalive interval.** ntfy sends a keepalive every 45 s by default, about 1,900 radio wake-ups a day. Raising it in `server.yml` cuts that:

```yaml
keepalive-interval: "2m"
```

Keep it below every idle timeout between the phone and ntfy: nginx's `proxy_read_timeout` (60 s by default; ntfy's example config uses 3 min), Cloudflare (about 100 s) and mobile carriers' NAT, which can drop idle connections after a few minutes. Don't go above 3 min unless you have checked. The app needs no setting; it adapts on its own.

**Measuring.** While unplugged, *Settings → Diagnostics* logs every 5 % of battery used with the rate in %/h for the whole phone. Compare days, or a day with **Silent Audio Keep-Alive** off. *iOS Settings → Battery → intfy* shows the app's share. Silent audio is the most expensive keep-alive, but turning it off makes iOS more likely to suspend the app.

## Limitations

- **Approximate location delivers updates rarely**, roughly every 15–20 minutes. The app should stay alive between them, but iOS behaviour over hours or days varies between versions. If iOS does suspend the app, messages arrive late (at the next wake-up or reconnect), but they are not lost while they remain in the server's cache.
- **A force-quit stops background delivery** until you open the app again.
- **Low Power Mode** and very low battery can make iOS more aggressive about suspending background apps.
- Without the time-sensitive entitlement, **time-sensitive notifications** may not break through Focus modes.
- **Free Apple ID signing** expires after 7 days. AltStore and SideStore can refresh it automatically.
- **Not included yet:** ntfy action buttons, inline image attachments, the `message_delete` and `message_clear` events, and publishing from the app beyond the test message.

## Troubleshooting

| Symptom | Check |
|---|---|
| Status shows *Retrying – Unauthorized* | Wrong token or password, or the user has no read access to the topic (HTTP 401/403). |
| *Not found (HTTP 404)* | The host or port is not an ntfy server, or there is a reverse-proxy path prefix. |
| Can't connect on the LAN | Allow *Local Network* in *Settings → intfy*. Make sure the server listens on `0.0.0.0`, not `127.0.0.1`. |
| Works in the foreground, not in the background | Open *Settings → Diagnostics*. "Not running for ~N min" means iOS suspended the app, and "ended without notice" means it was killed or crashed. Keep **Silent Audio Keep-Alive** on and location on **Always**, don't force-quit, and turn off Low Power Mode. If the log suggests a crash, look in *Settings → Privacy & Security → Analytics & Improvements → Analytics Data* for files starting with `Intfy`. |
| Messages arrive late after hours of inactivity | iOS suspended the app (see [Limitations](#limitations)). Compare the times in the app with the times on the server. |
| High battery use | See [Battery](#battery). Check *Settings → Diagnostics* for repeated "Network changed" or reconnect entries, raise the server's `keepalive-interval`, and compare the logged %/h. |
| No banners | Notifications must be allowed. Check that a Focus mode isn't hiding them. Priority 1–2 messages are silent on purpose. |

Check the stream directly from another machine:

```sh
curl -s http://192.168.1.10:80/alerts/json             # should print {"event":"open",...} and keepalives
curl -d "hello" -H "Title: test" http://192.168.1.10:80/alerts
```

## Testing without a real server

You can exercise the app in the iOS Simulator against any ntfy instance, or against a minimal ntfy-compatible mock. The simulator setup below skips the UI configuration:

```sh
DEV=<simulator-udid>
xcodebuild -project Intfy.xcodeproj -scheme Intfy -destination "id=$DEV" -derivedDataPath build/SimData build
xcrun simctl install $DEV build/SimData/Build/Products/Debug-iphonesimulator/Intfy.app

# preconfigure servers (a JSON array stored as Data in the app container's preferences)
PREFS="$(xcrun simctl get_app_container $DEV dev.intfy.app data)/Library/Preferences/dev.intfy.app"
HEX=$(printf '%s' '[{"name":"Home","host":"127.0.0.1","port":2586,"topics":["alerts"]}]' | xxd -p | tr -d '\n')
xcrun simctl spawn $DEV defaults write "$PREFS" servers -data $HEX
xcrun simctl privacy $DEV grant location-always dev.intfy.app
xcrun simctl location $DEV set 52.23,21.01
xcrun simctl launch $DEV dev.intfy.app
```

Send the app to the background (for example by launching `com.apple.Preferences`), publish a few messages, then return to the app. They should already be in the list with their original timestamps.

The simulator is a good check of the streaming logic. **Long-term background behaviour can only be verified on a real device**: for example, leave the phone overnight and compare the receive times in the app with the publish times on the server.

## Contributing

Bug reports and pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) covers building, signing with your own Apple ID, testing and the PR process. Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

intfy is released under the [MIT License](LICENSE).
