#!/usr/bin/env bash
# Builds an unsigned IPA for sideloading (AltStore / SideStore / Sideloadly / TrollStore).
# The sideloading tool re-signs it with your Apple ID.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR=build
CONFIGURATION=${CONFIGURATION:-Release}
# Versioned by commit, no tags: intfy-<short hash>.ipa ("dev" before the first commit).
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
IPA_NAME="intfy-$COMMIT.ipa"

xcodebuild \
  -project Intfy.xcodeproj \
  -scheme Intfy \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  INTFY_COMMIT="$COMMIT" \
  build

APP="$BUILD_DIR/DerivedData/Build/Products/$CONFIGURATION-iphoneos/Intfy.app"
rm -rf "$BUILD_DIR/Payload" "$BUILD_DIR"/intfy*.ipa
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP" "$BUILD_DIR/Payload/"
(cd "$BUILD_DIR" && zip -qry "$IPA_NAME" Payload)
rm -rf "$BUILD_DIR/Payload"

echo "IPA: $BUILD_DIR/$IPA_NAME"
# Let CI pick up the file name.
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "ipa_path=$BUILD_DIR/$IPA_NAME" >> "$GITHUB_OUTPUT"
  echo "ipa_name=${IPA_NAME%.ipa}" >> "$GITHUB_OUTPUT"
fi
