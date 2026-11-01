# Contributing

Thanks for helping out! Bug reports, fixes and small features are all welcome.

## Reporting a bug

[Open an issue](https://github.com/LofisMusk/intfy/issues) and include:

- iOS version and device
- ntfy server version, and whether there's a reverse proxy in front
- the commit you're on (*Settings → About*)
- what you expected and what happened

Missed or late notifications? Open *Settings → Diagnostics*, tap **Copy** and paste the log. It shows whether iOS froze the app, killed it, or the connection dropped.

Remove tokens, passwords and server addresses before posting anything.

## Building

See [Build](README.md#build) in the README. In short: Mac, Xcode 16+, `./scripts/build-ipa.sh`.

New `.swift` files under `Intfy/` are picked up automatically; no need to touch `project.pbxproj`.

## Testing

There are no unit tests yet, so test by running the app:

1. `./scripts/build-ipa.sh` must build without warnings.
2. Try it in the Simulator against an ntfy server (the `binwiederhier/ntfy` Docker image works fine).
3. If you touched the connection or background code, test on a real phone too. The Simulator never freezes apps in the background. Put what you saw in Diagnostics into the PR.

Want to skip the setup screen in the Simulator? Preload a server:

```sh
DEV=<simulator-udid>
xcodebuild -project Intfy.xcodeproj -scheme Intfy -destination "id=$DEV" -derivedDataPath build/SimData build
xcrun simctl install $DEV build/SimData/Build/Products/Debug-iphonesimulator/Intfy.app
PREFS="$(xcrun simctl get_app_container $DEV dev.intfy.app data)/Library/Preferences/dev.intfy.app"
HEX=$(printf '%s' '[{"name":"Home","host":"127.0.0.1","port":2586,"topics":["alerts"]}]' | xxd -p | tr -d '\n')
xcrun simctl spawn $DEV defaults write "$PREFS" servers -data $HEX
xcrun simctl privacy $DEV grant location-always dev.intfy.app
xcrun simctl launch $DEV dev.intfy.app
```

## Code style

- Match the code around you: Swift 5, SwiftUI, `@Observable` models, small view files in `Intfy/Views/`.
- Apple frameworks only. No packages unless there's a really good reason.
- Comment the *why* (iOS quirks, workarounds), not the *what*.
- Secrets go in the Keychain. Never log them or show them.
- UI text is in English.

## Pull requests

1. Fork, branch off `main`.
2. One fix or feature per PR. Small PRs get merged faster.
3. Commit messages in the imperative: "Add per-server sound", not "Added…".
4. Update the README if you change how something works or how to set it up.
5. Say in the PR what you changed and how you tested it.
6. Don't commit your `DEVELOPMENT_TEAM` or bundle ID.

Once merged into `main`, CI builds a release and pushes it to the SideStore/AltStore source, so it's installable right away.

By contributing you agree that your code is released under the [MIT License](LICENSE).
