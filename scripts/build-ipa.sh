#!/usr/bin/env bash
# Builds an unsigned IPA for sideloading (AltStore / SideStore / Sideloadly / TrollStore).
# The sideloading tool re-signs it with your Apple ID.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR=build
CONFIGURATION=${CONFIGURATION:-Release}
# Versioned by commit: intfy-<short hash>.ipa ("dev" before the first commit).
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
IPA_NAME="intfy-$COMMIT.ipa"

# Every build gets a higher version, so AltStore / SideStore sources can offer it as an update:
# <MARKETING_VERSION from the project>.<number of commits>, build number = number of commits.
# Needs the full history (CI checks out with fetch-depth: 0).
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
BASE_VERSION="$(grep -m 1 'MARKETING_VERSION = ' Intfy.xcodeproj/project.pbxproj | sed 's/.*= \([0-9.]*\);.*/\1/')"
VERSION="${BASE_VERSION:-1.0}.$BUILD_NUMBER"

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
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build

APP="$BUILD_DIR/DerivedData/Build/Products/$CONFIGURATION-iphoneos/Intfy.app"
rm -rf "$BUILD_DIR/Payload" "$BUILD_DIR"/intfy*.ipa
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP" "$BUILD_DIR/Payload/"
(cd "$BUILD_DIR" && zip -qry "$IPA_NAME" Payload)
rm -rf "$BUILD_DIR/Payload"

echo "IPA: $BUILD_DIR/$IPA_NAME (version $VERSION, build $BUILD_NUMBER)"
# Let CI pick up the file name.
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "ipa_path=$BUILD_DIR/$IPA_NAME" >> "$GITHUB_OUTPUT"
  echo "ipa_name=${IPA_NAME%.ipa}" >> "$GITHUB_OUTPUT"
  echo "app_path=$APP" >> "$GITHUB_OUTPUT"
  echo "version=$VERSION" >> "$GITHUB_OUTPUT"
fi
