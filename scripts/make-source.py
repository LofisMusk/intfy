#!/usr/bin/env python3
"""Builds the GitHub Pages site with an AltStore-format source (source.json).

The AltStore source format is what SideStore, AltStore, LiveContainer (with SideStore),
Feather and similar apps read. Adding the source once lets them install intfy and offer
every new release from main as an update.

The newest version is read from the built app's Info.plist; older versions are carried
over from the source currently published on Pages (up to --keep entries).

    scripts/make-source.py --app build/.../Intfy.app --ipa build/intfy-abc1234.ipa \
        --download-url https://github.com/.../intfy-abc1234.ipa \
        --site-url https://owner.github.io/intfy/ --out build/site
"""

import argparse
import html
import json
import os
import plistlib
import shutil
import subprocess
import urllib.request
from urllib.parse import quote

NAME = "intfy"
SUBTITLE = "ntfy notifications from your own server"
DESCRIPTION = (
    "intfy is a client for self-hosted ntfy servers. Messages arrive as local "
    "notifications, so it needs no APNs, no ntfy.sh relay and no Apple servers: "
    "your server talks only to your phone.\n\n"
    "It stays connected in the background using silent audio and approximate "
    "location as keep-alives. Location is never stored or sent anywhere."
)
TINT = "298087"  # Color.intfy
REPO_URL = "https://github.com/LofisMusk/intfy"
ICON_SOURCE = "Intfy/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
# Git trailers that only add noise to the "What's new" text.
SKIP_TRAILERS = ("Co-Authored-By:", "Claude-Session:", "Signed-off-by:")


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout.strip()


def release_notes():
    lines = [l for l in git("log", "-1", "--format=%B").splitlines() if not l.startswith(SKIP_TRAILERS)]
    return "\n".join(lines).strip()


def previous_versions(url):
    """Versions from the currently published source; empty on first publish or any error."""
    try:
        with urllib.request.urlopen(url, timeout=20) as response:
            source = json.load(response)
        return source["apps"][0].get("versions", [])
    except Exception as error:  # noqa: BLE001 – a missing history must never fail the release
        print(f"No previous source at {url} ({error}); starting a new history")
        return []


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, help="built Intfy.app")
    parser.add_argument("--ipa", required=True, help="the released IPA (for its size)")
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--site-url", required=True, help="Pages URL, ending in /")
    parser.add_argument("--out", required=True)
    parser.add_argument("--keep", type=int, default=15, help="versions to keep in the source")
    args = parser.parse_args()

    with open(os.path.join(args.app, "Info.plist"), "rb") as f:
        info = plistlib.load(f)

    site_url = args.site_url.rstrip("/") + "/"
    source_url = site_url + "source.json"
    icon_url = site_url + "icon.png"
    version = {
        "version": info["CFBundleShortVersionString"],
        "buildVersion": info["CFBundleVersion"],
        "date": git("log", "-1", "--format=%cI"),
        "localizedDescription": release_notes(),
        "downloadURL": args.download_url,
        "size": os.path.getsize(args.ipa),
        "minOSVersion": info.get("MinimumOSVersion", "17.0"),
    }
    history = [v for v in previous_versions(source_url) if v.get("version") != version["version"]]
    versions = [version, *history][: args.keep]

    app = {
        "name": NAME,
        "bundleIdentifier": info["CFBundleIdentifier"],
        "developerName": "LofisMusk",
        "subtitle": SUBTITLE,
        "localizedDescription": DESCRIPTION,
        "iconURL": icon_url,
        "tintColor": TINT,
        "category": "utilities",
        "screenshots": [],
        "versions": versions,
        # The IPA is unsigned and needs no entitlements; the sideloading app signs it.
        "appPermissions": {
            "entitlements": [],
            "privacy": {k: v for k, v in info.items() if k.endswith("UsageDescription")},
        },
        # Legacy fields for older SideStore / AltStore releases that predate "versions".
        "version": version["version"],
        "versionDate": version["date"],
        "versionDescription": version["localizedDescription"],
        "downloadURL": version["downloadURL"],
        "size": version["size"],
    }
    source = {
        "name": NAME,
        "identifier": "dev.intfy.source",
        "subtitle": SUBTITLE,
        "description": DESCRIPTION,
        "iconURL": icon_url,
        "website": REPO_URL,
        "tintColor": TINT,
        "apps": [app],
        "news": [],
    }

    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "source.json"), "w") as f:
        json.dump(source, f, indent=2, ensure_ascii=False)
        f.write("\n")
    shutil.copy(ICON_SOURCE, os.path.join(args.out, "icon.png"))
    with open(os.path.join(args.out, "index.html"), "w") as f:
        f.write(index_html(source_url, version))
    # Serve files as-is (no Jekyll processing).
    open(os.path.join(args.out, ".nojekyll"), "w").close()
    print(f"Source: {source_url} – {NAME} {version['version']} ({version['buildVersion']}), {len(versions)} versions")


def index_html(source_url, version):
    encoded = quote(source_url, safe="")
    url = html.escape(source_url)
    v = html.escape(f"{version['version']} ({version['buildVersion']})")
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>intfy source</title>
<link rel="icon" href="icon.png">
<style>
  :root {{ --bg: #f5f5f7; --card: #fff; --text: #1d1d1f; --muted: #6e6e73; --accent: #{TINT}; --line: #d2d2d7; }}
  @media (prefers-color-scheme: dark) {{
    :root {{ --bg: #000; --card: #1c1c1e; --text: #f5f5f7; --muted: #98989d; --line: #38383a; }}
  }}
  * {{ box-sizing: border-box; }}
  body {{ margin: 0; background: var(--bg); color: var(--text);
         font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }}
  main {{ max-width: 560px; margin: 0 auto; padding: 48px 16px; }}
  header {{ display: flex; gap: 16px; align-items: center; margin-bottom: 24px; }}
  header img {{ width: 72px; height: 72px; border-radius: 16px; }}
  h1 {{ margin: 0; font-size: 28px; }}
  p {{ margin: 0 0 12px; }}
  .muted {{ color: var(--muted); }}
  .card {{ background: var(--card); border-radius: 14px; padding: 20px; margin-bottom: 16px; }}
  .buttons {{ display: grid; gap: 10px; margin: 16px 0; }}
  a.button {{ display: block; text-align: center; padding: 12px; border-radius: 10px; font-weight: 600;
             background: var(--accent); color: #fff; text-decoration: none; }}
  a.button.secondary {{ background: transparent; color: var(--accent); border: 1px solid var(--line); }}
  code {{ display: block; padding: 10px 12px; border: 1px solid var(--line); border-radius: 8px;
         overflow-wrap: anywhere; font-size: 14px; user-select: all; }}
  a {{ color: var(--accent); }}
</style>
</head>
<body>
<main>
  <header>
    <img src="icon.png" alt="">
    <div>
      <h1>intfy</h1>
      <p class="muted">{html.escape(SUBTITLE)} · latest {v}</p>
    </div>
  </header>
  <div class="card">
    <p>Add this source once and your sideloading app installs intfy and offers every new build as an update.</p>
    <div class="buttons">
      <a class="button" href="sidestore://source?url={encoded}">Add to SideStore</a>
      <a class="button secondary" href="altstore://source?url={encoded}">Add to AltStore</a>
    </div>
    <p class="muted">LiveContainer, Feather and others: add this URL as a source.</p>
    <code>{url}</code>
  </div>
  <p class="muted"><a href="{REPO_URL}">Source code &amp; docs</a> · <a href="{REPO_URL}/releases">All releases</a></p>
</main>
</body>
</html>
"""


if __name__ == "__main__":
    main()
