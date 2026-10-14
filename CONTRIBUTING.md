# Contributing to intfy

Thanks for helping out! intfy is a small, dependency-free SwiftUI app. Bug reports, fixes and focused features are all welcome.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting bugs

Please [open an issue](https://github.com/LofisMusk/intfy/issues) that includes:

- your iOS version and device;
- your ntfy server version, and whether a reverse proxy sits in front of it;
- the commit you are running, shown in *Settings → About → Commit*;
- what you expected to happen and what happened instead.

**Background-delivery problems** (missed or late notifications) are much easier to track down with the diagnostics log. Open *Settings → Diagnostics*, tap **Copy** and paste the log into the issue. It shows whether iOS suspended the app, killed it, or whether the server dropped the connection.

**Never post tokens, passwords or private server addresses.** Redact them before pasting logs or screenshots.

## Building

You need a Mac with Xcode 16 or later. There are no package dependencies.

```sh
git clone https://github.com/LofisMusk/intfy.git
cd intfy
./scripts/build-ipa.sh          # unsigned build/intfy-<hash>.ipa, no signing setup needed
```

To run the app on your own device from Xcode, sign it with **your own** Apple ID:

```sh
cp Config/Signing.xcconfig.example Config/Signing.xcconfig
# set DEVELOPMENT_TEAM and a unique PRODUCT_BUNDLE_IDENTIFIER
```

`Config/Signing.xcconfig` is gitignored. Don't pick a team in Xcode's *Signing & Capabilities* tab, because that writes it into `project.pbxproj`, which is committed. A pull request containing a `DEVELOPMENT_TEAM` value will be asked to remove it.

The project uses Xcode's synchronized folders. A new `.swift` file placed under `Intfy/` is picked up automatically, so there is no need to edit `project.pbxproj`.

## Testing your change

The app has no unit test target yet; changes are verified by running the app. Before opening a PR:

1. Run `./scripts/build-ipa.sh`. It must build with **no warnings**.
2. Run the app in the Simulator against an ntfy server (the official `binwiederhier/ntfy` Docker image works well). [Testing without a real server](README.md#testing-without-a-real-server) in the README shows how to preconfigure a server from the command line.
3. If your change touches the connection or background behaviour, also test it on a real device. The Simulator does not reproduce iOS suspending apps or the Local Network permission. Include what you saw in *Settings → Diagnostics* in the PR description.

## Code style

- **Match the surrounding code.** That means Swift 5 language mode, `@MainActor` models, `@Observable` for UI state, and SwiftUI views split into small files under `Intfy/Views/`.
- **Keep it dependency-free.** Use Apple frameworks only. Adding a Swift package needs a strong reason.
- **Keep the UI text in English.** Use sentence case for footers and Title Case for buttons and navigation titles, as the existing screens do.
- **Comment the *why*:** iOS quirks, workarounds and protocol details. Well-named code doesn't need comments explaining *what* it does.
- **Never log or display secrets.** Credentials belong in the Keychain, never in `UserDefaults`.

## Pull requests

1. Fork the repo and create a branch from `main`.
2. Keep each PR focused on one fix or feature. Smaller PRs get reviewed faster.
3. Write commit messages in the imperative mood, e.g. "Add per-server notification sound", with a short body explaining *why* when it isn't obvious.
4. Update `README.md` if you change behaviour, settings or setup steps.
5. Open the PR against `main` and describe what changed and how you tested it.

Every push builds an IPA in GitHub Actions. On `main`, the workflow also publishes it as a release named `intfy-<short hash>`, so a change becomes installable as soon as it is merged.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
