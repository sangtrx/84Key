#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
pass=0
fail=0
ok()  { echo "  [PASS] $1"; pass=$((pass + 1)); }
bad() { echo "  [FAIL] $1"; fail=$((fail + 1)); }

echo "== SangKey distribution + ultra-light runtime invariants =="

app=platform/macos/App/SangKeyApp.mm
project=platform/macos/project.yml
release=.github/workflows/release.yml

if grep -R -n -E 'import Sparkle|package: Sparkle|SUFeedURL|SUPublicEDKey|SPUStandardUpdaterController' \
    "$project" platform/macos/Resources/Info.plist "$app" tools/package.sh "$release" >/dev/null 2>&1; then
  bad "embedded updater references are present"
else
  ok "no embedded auto-updater/appcast runtime"
fi

if grep -q 'github.com/sangtrx/SangKey/releases/latest' "$app" && \
   grep -q 'openURL:url' "$app" && \
   ! grep -qE 'NSURLSession|URLSession|URLRequest|downloadTask|dataTask|NSTask|Process\(|curl|wget' "$app"; then
  ok "update check is user-initiated browser navigation only"
else
  bad "update path gained an in-process downloader/network client"
fi

runtime_sensitive=$(grep -nE \
  'NSURLSession|URLSession|URLRequest|NSURLConnection|NWConnection|CFStream(Create|Open)|socket\(|NSPasteboard|SecItem(CopyMatching|Add|Update|Delete)' \
  "$app" platform/macos/Input/InputController.mm || true)
if [ -z "$runtime_sensitive" ]; then ok "runtime has no direct network/clipboard/Keychain client"; else echo "$runtime_sensitive"; bad "sensitive runtime API added"; fi

if awk '/applicationDidFinishLaunching/,/loadDictionaries/' "$app" | grep -q 'unsetenv("KEY84_TRACE")'; then
  ok "diagnostic key trace is scrubbed before interception"
else
  bad "KEY84_TRACE can reach the hardened runtime"
fi

if grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.sangtrx.sangkey$' "$project" && \
   grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.sangtrx.sangkey.debug$' "$project"; then
  ok "SangKey uses independent TCC/code-sign identities"
else
  bad "SangKey bundle identity is not isolated"
fi

swift_sources=$(find platform/macos/App platform/macos/Bridge -type f -name '*.swift' -print 2>/dev/null || true)
if [ -z "$swift_sources" ] && \
   grep -q -- '- path: App/SangKeyApp.mm' "$project" && \
   ! grep -qE 'SWIFT_VERSION|SWIFT_OBJC_BRIDGING_HEADER|ServiceManagement\.framework' "$project"; then
  ok "macOS host is Objective-C++ only: no Swift, SwiftUI, Combine, bridge, or ServiceManagement"
else
  [ -n "$swift_sources" ] && echo "$swift_sources"
  bad "non-minimal Swift/ServiceManagement host machinery remains"
fi

if grep -q 'NSStatusBar.*statusItemWithLength' "$app" && \
   grep -q 'NSMenu \*_menu' "$app" && \
   ! grep -qE 'NSWindowController|NSHosting|NSViewController' "$app"; then
  ok "idle UI is status-item/menu only; no persistent settings window graph"
else
  bad "idle UI gained persistent window/view-controller machinery"
fi

if grep -q 'NSAlert \*alert' "$app" && ! grep -q 'Onboarding' "$project"; then
  ok "first-run permission prompt is transient AppKit NSAlert"
else
  bad "first-run UI can retain a heavyweight onboarding graph"
fi

if ! grep -R -qE 'ServiceManagement|SMAppService|runOnStartup' "$app" "$project"; then
  ok "launch-at-login framework/state removed from the keyboard process"
else
  bad "login-item machinery remains in the ultra-light runtime"
fi

mutable_uses=$(grep -R -nE '^[[:space:]]*-[[:space:]]+uses:[[:space:]]+[^@]+@[^#[:space:]]+' .github/workflows \
  | grep -vE '@[0-9a-f]{40}([[:space:]]|$)' || true)
if [ -z "$mutable_uses" ]; then ok "GitHub Actions are immutable-SHA pinned"; else echo "$mutable_uses"; bad "mutable GitHub Action ref"; fi

EXPECTED_XCODEGEN_SHA=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
if grep -q "$EXPECTED_XCODEGEN_SHA" .github/workflows/ci.yml && grep -q "$EXPECTED_XCODEGEN_SHA" "$release"; then
  ok "XcodeGen is checksum pinned"
else
  bad "XcodeGen dependency is not deterministic"
fi

build_block=$(awk '/^  build-sign-notarize:/,/^  publish:/' "$release")
publish_block=$(awk '/^  publish:/,0' "$release")
if echo "$build_block" | grep -q 'contents: read' && ! echo "$build_block" | grep -q 'contents: write' && \
   echo "$publish_block" | grep -q 'contents: write' && ! echo "$publish_block" | grep -q 'secrets\.'; then
  ok "signing secrets are isolated from release write permission"
else
  bad "release workflow mixes secrets and write permission"
fi

cleanup_line=$(grep -n -- '- name: Clean up signing material' "$release" | cut -d: -f1)
upload_line=$(grep -n -- '- name: Upload notarized release payload' "$release" | cut -d: -f1)
if [ -n "$cleanup_line" ] && [ -n "$upload_line" ] && [ "$cleanup_line" -lt "$upload_line" ]; then
  ok "signing material is deleted before artifact handoff"
else
  bad "artifact handoff can see signing material"
fi

preflight_block=$(awk '/^  preflight:/,/^  build-sign-notarize:/' "$release")
if echo "$preflight_block" | grep -q 'refs/remotes/origin/main' && \
   echo "$preflight_block" | grep -q 'run_tests.sh' && \
   echo "$preflight_block" | grep -q 'MARKETING_VERSION' && \
   echo "$build_block" | grep -q 'needs: preflight'; then
  ok "release signing is gated by tested exact-main provenance"
else
  bad "release provenance gate is incomplete"
fi

if grep -q 'isRunning.*hasAccessibilityPermission\|isRunning]' "$app" && \
   grep -q 'tryStartInput' "$app"; then
  ok "event tap itself is the effective runtime-permission signal"
else
  bad "Accessibility lifecycle no longer follows the event tap"
fi

if grep -q 'github.com/sangtrx/SangKey/releases/latest' "$app" && \
   grep -q 'derived from 84Key/OpenKey' platform/macos/Resources/Info.plist; then
  ok "SangKey brand and upstream provenance are both explicit"
else
  bad "brand/provenance metadata is inconsistent"
fi

if grep -q "SANGKEY_ARCHS: 'arm64 x86_64'" .github/workflows/ci.yml && \
   grep -q "SANGKEY_ARCHS: 'arm64 x86_64'" "$release" && \
   grep -q 'lipo .* -verify_arch arm64 x86_64' .github/workflows/ci.yml && \
   grep -q 'lipo .* -verify_arch arm64 x86_64' "$release"; then
  ok "CI and release require universal arm64+x86_64 binaries"
else
  bad "release architecture is not universal and verified"
fi

UPLOAD_V6=b7c566a772e6b6bfb58ed0dc250532a479d7789f
DOWNLOAD_V7=37930b1c2abaa49bbe596cd826c3c89aef350131
if grep -q "actions/upload-artifact@$UPLOAD_V6" "$release" && grep -q "actions/download-artifact@$DOWNLOAD_V7" "$release"; then
  ok "artifact handoff uses reviewed Node 24 action pins"
else
  bad "artifact handoff action pins changed"
fi

if grep -Fq '#define CHR(index) (((index) >= 0 && (index) < MAX_BUFF)' core/engine/DataType.h; then
  ok "legacy typing-buffer accessor remains bounds checked"
else
  bad "CHR() can read outside the typing buffer"
fi

if grep -q '/usr/bin/base64 -D' "$release" && grep -q 'Smoke-test release credential decoder' .github/workflows/ci.yml; then
  ok "macOS-native release credential decoder is smoke tested"
else
  bad "release credential decoder is not portability tested"
fi

EXPECTED_ENGINE_BLOB=31ed888056436edeb13145c309392b0642f88e7c
if [ "$(git hash-object core/engine/EngineUpstream.inc)" = "$EXPECTED_ENGINE_BLOB" ] && \
   grep -q '#include "EngineUpstream.inc"' core/engine/Engine.cpp && \
   grep -q 'vInputType != vVNI' core/engine/Engine.cpp && \
   grep -q 'dashboard1 ok => dashboard1 ok' core/tests/cases/backspace_restore.txt && \
   grep -q 'expectEq(st, "J7", "a61", "ấ")' core/tests/engine_test.cpp; then
  ok "legacy engine bytes remain pinned behind Telex/VNI regression gates"
else
  bad "engine provenance or numeric-boundary gate changed"
fi

if grep -q 'name: SangKey' "$project" && \
   grep -q 'MARKETING_VERSION: "0.3.0"' "$project" && \
   grep -q 'APP_NAME="SangKey"' tools/package.sh; then
  ok "product/build identity is consistently SangKey 0.3.0"
else
  bad "product identity is mixed between 84Key and SangKey"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
