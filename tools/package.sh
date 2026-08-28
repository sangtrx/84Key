#!/bin/bash
# package.sh — build SangKey.app and a DMG, optionally notarized.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MACOS="$ROOT/platform/macos"
BUILD="$ROOT/build"
CONFIG="${CONFIG:-Release}"
APP_NAME="SangKey"
AGENT_IDENTIFIER="com.sangtrx.sangkey.agent"
NOTARY_PROFILE="${SANGKEY_NOTARY_PROFILE:-}"
REQUIRE_DEVELOPER_ID="${SANGKEY_REQUIRE_DEVELOPER_ID:-0}"
EXPECTED_TEAM_ID="${SANGKEY_EXPECTED_TEAM_ID:-}"
SOURCE_URL="${SANGKEY_SOURCE_URL:-https://github.com/sangtrx/84Key/tree/$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo main)}"

command -v xcodegen >/dev/null 2>&1 || {
  echo "ERROR: xcodegen is required; see docs/BUILD.md" >&2
  exit 1
}

( cd "$MACOS" && xcodegen generate >/dev/null )

NOTARY_ARGS=()
if [ -n "$NOTARY_PROFILE" ]; then
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
elif [ -n "${SANGKEY_ASC_KEY_PATH:-}" ]; then
  NOTARY_ARGS=(--key "$SANGKEY_ASC_KEY_PATH" \
               --key-id "${SANGKEY_ASC_KEY_ID:?SANGKEY_ASC_KEY_ID is required with SANGKEY_ASC_KEY_PATH}" \
               --issuer "${SANGKEY_ASC_ISSUER_ID:?SANGKEY_ASC_ISSUER_ID is required with SANGKEY_ASC_KEY_PATH}")
fi

if [ -z "${CODESIGN_IDENTITY:-}" ]; then
  CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
      | awk -F'"' '/Developer ID Application/{print $2; exit}')"
  if [ -z "$CODESIGN_IDENTITY" ] && { [ "$REQUIRE_DEVELOPER_ID" = "1" ] || [ ${#NOTARY_ARGS[@]} -gt 0 ]; }; then
    echo "ERROR: a Developer ID Application identity is required for a notarized/release build" >&2
    exit 1
  fi
  if [ -z "$CODESIGN_IDENTITY" ]; then
    CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Apple Development/{print $2; exit}')"
  fi
fi

if [ "$REQUIRE_DEVELOPER_ID" = "1" ] && [ -z "$EXPECTED_TEAM_ID" ]; then
  echo "ERROR: SANGKEY_EXPECTED_TEAM_ID is required for release identity verification" >&2
  exit 1
fi

TS="--timestamp=none"
[ ${#NOTARY_ARGS[@]} -gt 0 ] && TS="--timestamp"

rm -rf "$BUILD"
mkdir -p "$BUILD"
VERSION_OVERRIDE=()
[ -n "${SANGKEY_VERSION:-}" ] && VERSION_OVERRIDE=(MARKETING_VERSION="$SANGKEY_VERSION")
ARCH_OVERRIDE=()
if [ -n "${SANGKEY_ARCHS:-}" ]; then
  ARCH_OVERRIDE=(ARCHS="$SANGKEY_ARCHS" ONLY_ACTIVE_ARCH=NO)
  echo "Architectures: $SANGKEY_ARCHS"
fi

xcodebuild -project "$MACOS/$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
  -configuration "$CONFIG" -derivedDataPath "$BUILD/dd" \
  CODE_SIGNING_ALLOWED=NO "${VERSION_OVERRIDE[@]}" "${ARCH_OVERRIDE[@]}" \
  build >/dev/null

APP="$BUILD/dd/Build/Products/$CONFIG/$APP_NAME.app"
AGENT="$APP/Contents/Resources/SangKeyAgent"
AGENT_PLIST="$APP/Contents/Library/LaunchAgents/com.sangtrx.sangkey.agent.plist"
[ -d "$APP" ] || { echo "ERROR: build did not produce $APP" >&2; exit 1; }
[ -x "$AGENT" ] || { echo "ERROR: embedded SangKeyAgent is missing" >&2; exit 1; }
[ -f "$AGENT_PLIST" ] || { echo "ERROR: bundled LaunchAgent plist is missing" >&2; exit 1; }

codesign_field() {
  local target="$1" field="$2"
  codesign -d --verbose=4 "$target" 2>&1 | awk -F= -v field="$field" '$1 == field {print $2; exit}'
}

if [ -n "$CODESIGN_IDENTITY" ]; then
  # A command-line tool does not carry a bundle Info.plist by default, so pin
  # its code-signing identifier explicitly. This keeps the agent's designated
  # requirement/TCC identity stable across builds instead of falling back to a
  # filename-derived identifier.
  codesign --force --identifier "$AGENT_IDENTIFIER" --options runtime $TS \
    -s "$CODESIGN_IDENTITY" "$AGENT"
  codesign --verify --strict --verbose=2 "$AGENT"
  ACTUAL_AGENT_IDENTIFIER="$(codesign_field "$AGENT" Identifier)"
  [ "$ACTUAL_AGENT_IDENTIFIER" = "$AGENT_IDENTIFIER" ] || {
    echo "ERROR: SangKeyAgent codesign identifier is '$ACTUAL_AGENT_IDENTIFIER'" >&2
    exit 1
  }

  # Sign the enclosing app only after its nested executable has final identity.
  codesign --force --options runtime $TS -s "$CODESIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"

  if [ "$REQUIRE_DEVELOPER_ID" = "1" ]; then
    AGENT_AUTHORITY="$(codesign_field "$AGENT" Authority)"
    APP_AUTHORITY="$(codesign_field "$APP" Authority)"
    AGENT_TEAM="$(codesign_field "$AGENT" TeamIdentifier)"
    APP_TEAM="$(codesign_field "$APP" TeamIdentifier)"
    [[ "$AGENT_AUTHORITY" == "Developer ID Application:"* ]] || {
      echo "ERROR: agent signer is not Developer ID Application: '$AGENT_AUTHORITY'" >&2
      exit 1
    }
    [[ "$APP_AUTHORITY" == "Developer ID Application:"* ]] || {
      echo "ERROR: app signer is not Developer ID Application: '$APP_AUTHORITY'" >&2
      exit 1
    }
    [ "$AGENT_TEAM" = "$EXPECTED_TEAM_ID" ] || {
      echo "ERROR: agent TeamIdentifier '$AGENT_TEAM' != expected '$EXPECTED_TEAM_ID'" >&2
      exit 1
    }
    [ "$APP_TEAM" = "$EXPECTED_TEAM_ID" ] || {
      echo "ERROR: app TeamIdentifier '$APP_TEAM' != expected '$EXPECTED_TEAM_ID'" >&2
      exit 1
    }
  fi
fi

DIST="$BUILD/dist"
mkdir -p "$DIST"
cp -R "$APP" "$DIST/"
ln -sf /Applications "$DIST/Applications"
cp "$ROOT/LICENSE" "$DIST/LICENSE.txt"
cp "$ROOT/NOTICE" "$DIST/NOTICE.txt"
cp "$ROOT/core/data/ENGLISH_WORDS_PROVENANCE.md" "$DIST/THIRD_PARTY_DATA.txt"
printf 'Corresponding source for this build:\n%s\n' "$SOURCE_URL" > "$DIST/SOURCE.txt"

DMG="$BUILD/$APP_NAME.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$DIST" -ov -format UDZO "$DMG" >/dev/null

if [ -n "$CODESIGN_IDENTITY" ]; then
  codesign --force $TS -s "$CODESIGN_IDENTITY" "$DMG"
  codesign --verify --verbose=2 "$DMG"
fi

shasum -a 256 "$DMG"

if [ ${#NOTARY_ARGS[@]} -gt 0 ]; then
  NOTARY_TIMEOUT="${SANGKEY_NOTARY_TIMEOUT:-20m}"
  attempt=1
  until xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait --timeout "$NOTARY_TIMEOUT"; do
    if [ "$attempt" -ge 2 ]; then
      echo "ERROR: notarization failed/stalled after $attempt attempts" >&2
      exit 1
    fi
    attempt=$((attempt + 1))
  done
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl -a -t open --context context:primary-signature "$DMG"
else
  echo "NOTE: local package is not notarized; release CI supplies notarization credentials."
fi
