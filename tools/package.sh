#!/bin/bash
#
# package.sh — build 84Key.app and a .dmg, and (optionally) notarize the .dmg so
# it opens cleanly on other Macs.
#
# This hardened fork intentionally has no in-app auto-updater. The produced DMG
# contains only the application and its Apple-signed system-framework links.
#
# Signing:
#   - Auto-detects a stable signing identity (Developer ID preferred, else Apple
#     Development). Override with CODESIGN_IDENTITY. A stable identity keeps the
#     macOS Accessibility/TCC grant valid across rebuilds.
#   - Falls back to ad-hoc if no identity is found (local use only).
#
# Notarization (to share with others) — two ways to supply credentials:
#   A) Local: a notarytool keychain profile.
#   B) CI / unattended: an App Store Connect API key (.p8). Set:
#        KEY84_ASC_KEY_PATH=/path/to/AuthKey_XXXX.p8
#        KEY84_ASC_KEY_ID=<Key ID>
#        KEY84_ASC_ISSUER_ID=<Issuer ID>
#
# Other env overrides:
#   CODESIGN_IDENTITY  — signing identity (else auto-detected from the keychain).
#   KEY84_VERSION      — override MARKETING_VERSION (e.g. from a release tag).
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MACOS="$ROOT/platform/macos"
BUILD="$ROOT/build"
CONFIG="${CONFIG:-Release}"
APP_NAME="84Key"
NOTARY_PROFILE="${KEY84_NOTARY_PROFILE:-}"

command -v xcodegen >/dev/null 2>&1 || {
  echo "ERROR: xcodegen is required; see docs/BUILD.md" >&2
  exit 1
}

echo "==> Generating Xcode project (XcodeGen)"
( cd "$MACOS" && xcodegen generate >/dev/null )

if [ -z "${CODESIGN_IDENTITY:-}" ]; then
  CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
      | awk -F'"' '/Developer ID Application/{print $2; exit}')"
  [ -z "$CODESIGN_IDENTITY" ] && CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
      | awk -F'"' '/Apple Development/{print $2; exit}')"
fi

NOTARY_ARGS=()
if [ -n "$NOTARY_PROFILE" ]; then
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
elif [ -n "${KEY84_ASC_KEY_PATH:-}" ]; then
  NOTARY_ARGS=(--key "$KEY84_ASC_KEY_PATH" \
               --key-id "${KEY84_ASC_KEY_ID:?KEY84_ASC_KEY_ID is required with KEY84_ASC_KEY_PATH}" \
               --issuer "${KEY84_ASC_ISSUER_ID:?KEY84_ASC_ISSUER_ID is required with KEY84_ASC_KEY_PATH}")
fi

# Notarization requires a secure timestamp; local ad-hoc/development packages do
# not need to contact the timestamp service.
TS="--timestamp=none"
[ ${#NOTARY_ARGS[@]} -gt 0 ] && TS="--timestamp"

echo "==> Building $CONFIG"
rm -rf "$BUILD"
mkdir -p "$BUILD"
VERSION_OVERRIDE=()
[ -n "${KEY84_VERSION:-}" ] && VERSION_OVERRIDE=(MARKETING_VERSION="$KEY84_VERSION")
xcodebuild -project "$MACOS/$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
  -configuration "$CONFIG" -derivedDataPath "$BUILD/dd" \
  CODE_SIGNING_ALLOWED=NO "${VERSION_OVERRIDE[@]}" \
  build >/dev/null

APP="$BUILD/dd/Build/Products/$CONFIG/$APP_NAME.app"
[ -d "$APP" ] || { echo "ERROR: build did not produce $APP" >&2; exit 1; }

if [ -n "$CODESIGN_IDENTITY" ]; then
  echo "==> Signing app with: $CODESIGN_IDENTITY"
  codesign --force --options runtime $TS -s "$CODESIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
else
  echo "    (ad-hoc build — no Developer ID/Apple Development identity found)"
fi

echo "==> Staging app and building DMG"
DIST="$BUILD/dist"
mkdir -p "$DIST"
cp -R "$APP" "$DIST/"
ln -sf /Applications "$DIST/Applications"

DMG="$BUILD/$APP_NAME.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$DIST" -ov -format UDZO "$DMG" >/dev/null

if [ -n "$CODESIGN_IDENTITY" ]; then
  codesign --force $TS -s "$CODESIGN_IDENTITY" "$DMG"
  codesign --verify --verbose=2 "$DMG"
fi

echo ""
echo "==> Built"
echo "    App: $APP"
echo "    DMG: $DMG"
shasum -a 256 "$DMG"

if [ ${#NOTARY_ARGS[@]} -gt 0 ]; then
  echo ""
  echo "==> Notarizing"
  NOTARY_TIMEOUT="${KEY84_NOTARY_TIMEOUT:-20m}"
  attempt=1
  until xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" \
        --wait --timeout "$NOTARY_TIMEOUT"; do
    if [ "$attempt" -ge 2 ]; then
      echo "ERROR: notarization failed/stalled after $attempt attempts" >&2
      exit 1
    fi
    echo "==> Notarization attempt $attempt failed; retrying once" >&2
    attempt=$((attempt + 1))
  done
  echo "==> Stapling"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  echo "==> Notarized DMG ready: $DMG"
else
  cat <<'NOTE'

NOTE: Not notarized — Gatekeeper can warn on another Mac. For a distributable
build, supply a notarytool keychain profile or the App Store Connect API-key
environment variables documented above.
NOTE
fi
