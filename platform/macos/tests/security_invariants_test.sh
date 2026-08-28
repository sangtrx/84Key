#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
pass=0
fail=0
ok()  { echo "  [PASS] $1"; pass=$((pass + 1)); }
bad() { echo "  [FAIL] $1"; fail=$((fail + 1)); }

echo "== SangKey v0.4 split-process security + footprint invariants =="

app=platform/macos/App/SangKeyApp.mm
agent=platform/macos/Agent/SangKeyAgent.mm
agent_plist=platform/macos/Agent/com.sangtrx.sangkey.agent.plist
compat=platform/macos/HeadlessCompat/AppKitCompat.mm
prefs=platform/macos/Shared/SangKeyPreferences.mm
project=platform/macos/project.yml
ci=.github/workflows/ci.yml
release=.github/workflows/release.yml
package=tools/package.sh

if grep -R -n -E 'import Sparkle|package: Sparkle|SUFeedURL|SUPublicEDKey|SPUStandardUpdaterController' \
    "$project" platform/macos/Resources/Info.plist "$app" "$agent" "$package" "$release" >/dev/null 2>&1; then
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
  "$agent" platform/macos/Input/InputController.mm "$compat" || true)
if [ -z "$runtime_sensitive" ]; then
  ok "always-on input process has no direct network/clipboard/Keychain client"
else
  echo "$runtime_sensitive"
  bad "sensitive API added to always-on input process"
fi

if awk '/int main/,/InputController \*input/' "$agent" | grep -q 'unsetenv("KEY84_TRACE")'; then
  ok "diagnostic key trace is scrubbed before agent initializes interception"
else
  bad "KEY84_TRACE can reach the hardened input agent"
fi

if grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.sangtrx.sangkey$' "$project" && \
   grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.sangtrx.sangkey.debug$' "$project" && \
   grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.sangtrx.sangkey.agent$' "$project"; then
  ok "launcher/debug/agent identities are explicit"
else
  bad "SangKey code identities are incomplete"
fi

swift_sources=$(find platform/macos/App platform/macos/Agent platform/macos/Shared platform/macos/HeadlessCompat \
  -type f -name '*.swift' -print 2>/dev/null || true)
if [ -z "$swift_sources" ] && ! grep -qE 'SWIFT_VERSION|SWIFT_OBJC_BRIDGING_HEADER' "$project"; then
  ok "launcher and agent remain zero-Swift"
else
  [ -n "$swift_sources" ] && echo "$swift_sources"
  bad "Swift runtime source/build machinery was introduced"
fi

agent_block=$(awk '/^  SangKeyAgent:/,/^  SangKey:/' "$project")
app_block=$(awk '/^  SangKey:$/,/^schemes:/' "$project")
if echo "$agent_block" | grep -q 'Foundation.framework' && \
   echo "$agent_block" | grep -q 'ApplicationServices.framework' && \
   echo "$agent_block" | grep -q 'Carbon.framework' && \
   echo "$agent_block" | grep -q 'Security.framework' && \
   ! echo "$agent_block" | grep -qE 'AppKit.framework|ServiceManagement.framework|SwiftUI|Combine'; then
  ok "always-on agent build graph excludes AppKit/ServiceManagement/Swift UI"
else
  bad "always-on agent build graph is not headless"
fi

if echo "$app_block" | grep -q 'AppKit.framework' && \
   echo "$app_block" | grep -q 'ServiceManagement.framework' && \
   ! echo "$app_block" | grep -q 'path: Input' && \
   ! echo "$app_block" | grep -q '../../core/engine'; then
  ok "ephemeral control app owns UI/login registration but not the typing engine"
else
  bad "control app and input engine are not cleanly separated"
fi

if grep -q 'agentServiceWithPlistName:kAgentPlist' "$app" && \
   grep -q 'registerAndReturnError' "$app" && \
   grep -q 'unregisterAndReturnError' "$app" && \
   grep -q 'ServiceManagement/ServiceManagement.h' "$app"; then
  ok "background agent uses SMAppService registration"
else
  bad "background-agent lifecycle is not owned by SMAppService"
fi

if grep -q '<key>BundleProgram</key>' "$agent_plist" && \
   grep -q '<string>Contents/Resources/SangKeyAgent</string>' "$agent_plist" && \
   grep -q '<key>KeepAlive</key>' "$agent_plist" && \
   grep -q '<string>Aqua</string>' "$agent_plist" && \
   grep -q 'Contents/Library/LaunchAgents' "$project"; then
  ok "LaunchAgent is bundled inside the app and points at embedded agent"
else
  bad "bundled LaunchAgent layout is inconsistent"
fi

if ! grep -R -qE '(^|[^A-Za-z])(launchctl|~/Library/LaunchAgents|/Library/LaunchAgents)' \
    "$app" "$agent" "$package" "$project"; then
  ok "runtime/install path does not mutate LaunchAgents or shell out to launchctl"
else
  bad "manual launchctl/LaunchAgents mutation was introduced"
fi

if grep -q 'SangKeyPreferencesDomain = @"com.sangtrx.sangkey"' "$prefs" && \
   grep -q 'CFPreferencesCopyValue' "$prefs" && \
   grep -q 'CFPreferencesSetValue' "$prefs" && \
   grep -q 'CFNotificationCenterGetDarwinNotifyCenter' "$prefs" && \
   grep -q 'SangKeyCurrentEngineOptions' "$agent"; then
  ok "launcher and agent share an explicit preferences domain via Darwin notification"
else
  bad "split-process preference propagation is incomplete"
fi

if grep -q 'SANGKEY_AGENT_CI_SMOKE' "$agent" && \
   grep -q 'dictionaries=yes; AppKit=no' "$agent" && \
   grep -q 'RSS_KIB.*30720\|30720' "$ci"; then
  ok "CI has a deterministic no-TCC agent smoke and 30 MiB RSS budget"
else
  bad "headless runtime footprint is not continuously gated"
fi

if grep -q 'SangKeyAgent' "$package" && \
   grep -q 'codesign --force --options runtime.*"\$AGENT"' "$package" && \
   grep -q 'codesign --verify --deep --strict.*"\$APP"' "$package"; then
  ok "nested agent is signed before the enclosing app and deep-verified"
else
  bad "nested-code signing order/verification is incomplete"
fi

if grep -q 'lipo "\$AGENT" -verify_arch arm64 x86_64' "$ci" && \
   grep -q 'lipo "\$AGENT" -verify_arch arm64 x86_64' "$release" && \
   grep -q "SANGKEY_ARCHS: 'arm64 x86_64'" "$ci" && \
   grep -q "SANGKEY_ARCHS: 'arm64 x86_64'" "$release"; then
  ok "CI and release require a universal headless agent"
else
  bad "agent architecture is not universally verified"
fi

if grep -q "otool -L \"\$AGENT\"" "$ci" && \
   grep -qE "grep -Eqi 'AppKit\|SwiftUI\|Combine\|/libswift\|ServiceManagement'" "$ci" && \
   grep -qE "grep -Eqi 'AppKit\|SwiftUI\|Combine\|/libswift\|ServiceManagement'" "$release"; then
  ok "dynamic linkage gates forbid UI/Swift/login frameworks in the agent"
else
  bad "agent linkage invariants are not enforced dynamically"
fi

mutable_uses=$(grep -R -nE '^[[:space:]]*-[[:space:]]+uses:[[:space:]]+[^@]+@[^#[:space:]]+' .github/workflows \
  | grep -vE '@[0-9a-f]{40}([[:space:]]|$)' || true)
if [ -z "$mutable_uses" ]; then
  ok "GitHub Actions are immutable-SHA pinned"
else
  echo "$mutable_uses"
  bad "mutable GitHub Action ref"
fi

EXPECTED_XCODEGEN_SHA=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
if grep -q "$EXPECTED_XCODEGEN_SHA" "$ci" && grep -q "$EXPECTED_XCODEGEN_SHA" "$release"; then
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

UPLOAD_V6=b7c566a772e6b6bfb58ed0dc250532a479d7789f
DOWNLOAD_V7=37930b1c2abaa49bbe596cd826c3c89aef350131
if grep -q "actions/upload-artifact@$UPLOAD_V6" "$release" && \
   grep -q "actions/download-artifact@$DOWNLOAD_V7" "$release"; then
  ok "artifact handoff uses reviewed Node 24 action pins"
else
  bad "artifact handoff action pins changed"
fi

if grep -Fq '#define CHR(index) (((index) >= 0 && (index) < MAX_BUFF)' core/engine/DataType.h; then
  ok "legacy typing-buffer accessor remains bounds checked"
else
  bad "CHR() can read outside the typing buffer"
fi

if grep -q '/usr/bin/base64 -D' "$release" && grep -q 'Smoke-test release credential decoder' "$ci"; then
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
   grep -q 'MARKETING_VERSION: "0.4.0"' "$project" && \
   grep -q 'CURRENT_PROJECT_VERSION: "14"' "$project" && \
   grep -q 'APP_NAME="SangKey"' "$package"; then
  ok "product/build identity is consistently SangKey 0.4.0 build 14"
else
  bad "product identity/version is inconsistent"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
