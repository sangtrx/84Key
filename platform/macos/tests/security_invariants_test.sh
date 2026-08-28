#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
pass=0
fail=0
ok()  { echo "  [PASS] $1"; pass=$((pass + 1)); }
bad() { echo "  [FAIL] $1"; fail=$((fail + 1)); }
check() { if eval "$1"; then ok "$2"; else bad "$2"; fi; }

echo "== SangKey v0.4 security + distribution invariants =="

app=platform/macos/App/SangKeyApp.mm
agent=platform/macos/Agent/SangKeyAgent.mm
agent_plist=platform/macos/Agent/com.sangtrx.sangkey.agent.plist
compat=platform/macos/HeadlessCompat/AppKitCompat.mm
prefs=platform/macos/Shared/SangKeyPreferences.mm
project=platform/macos/project.yml
ci=.github/workflows/ci.yml
release=.github/workflows/release.yml
package=tools/package.sh
gen_dict=tools/gen_dict.py

# Runtime/privacy surface.
if grep -R -n -E 'import Sparkle|package: Sparkle|SUFeedURL|SUPublicEDKey|SPUStandardUpdaterController' \
    "$project" platform/macos/Resources/Info.plist "$app" "$agent" "$package" "$release" >/dev/null 2>&1; then
  bad "no embedded auto-updater/appcast runtime"
else
  ok "no embedded auto-updater/appcast runtime"
fi

check "grep -q 'github.com/sangtrx/84Key/releases/latest' '$app' && grep -q 'openURL:url' '$app' && ! grep -qE 'NSURLSession|URLSession|URLRequest|downloadTask|dataTask|NSTask|Process\\(|curl|wget' '$app'" \
      "manual update check opens the currently live repository only"

runtime_sensitive=$(grep -nE \
  'NSURLSession|URLSession|URLRequest|NSURLConnection|NWConnection|CFStream(Create|Open)|socket\(|NSPasteboard|SecItem(CopyMatching|Add|Update|Delete)' \
  "$agent" platform/macos/Input/InputController.mm "$compat" || true)
if [ -z "$runtime_sensitive" ]; then ok "always-on agent has no network/clipboard/Keychain client"; else echo "$runtime_sensitive"; bad "always-on agent has no network/clipboard/Keychain client"; fi

check "awk '/int main/,/InputController \\*input/' '$agent' | grep -q 'unsetenv(\"KEY84_TRACE\")'" \
      "diagnostic key trace is scrubbed before interception"

# Product identity + split runtime.
check "grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.sangtrx.sangkey$' '$project' && grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.sangtrx.sangkey.debug$' '$project' && grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.sangtrx.sangkey.agent$' '$project'" \
      "launcher/debug/agent identities are explicit"

swift_sources=$(find platform/macos/App platform/macos/Agent platform/macos/Shared platform/macos/HeadlessCompat -type f -name '*.swift' -print 2>/dev/null || true)
if [ -z "$swift_sources" ] && ! grep -qE 'SWIFT_VERSION|SWIFT_OBJC_BRIDGING_HEADER' "$project"; then ok "launcher and agent remain zero-Swift"; else bad "launcher and agent remain zero-Swift"; fi

agent_block=$(awk '/^  SangKeyAgent:/,/^  SangKey:/' "$project")
app_block=$(awk '/^  SangKey:$/,/^schemes:/' "$project")
if echo "$agent_block" | grep -q 'Foundation.framework' && echo "$agent_block" | grep -q 'ApplicationServices.framework' && echo "$agent_block" | grep -q 'Carbon.framework' && echo "$agent_block" | grep -q 'Security.framework' && ! echo "$agent_block" | grep -qE 'AppKit.framework|ServiceManagement.framework|SwiftUI|Combine'; then ok "always-on agent build graph stays headless"; else bad "always-on agent build graph stays headless"; fi
if echo "$app_block" | grep -q 'AppKit.framework' && echo "$app_block" | grep -q 'ServiceManagement.framework' && ! echo "$app_block" | grep -q 'path: Input' && ! echo "$app_block" | grep -q '../../core/engine'; then ok "control app does not own the typing engine"; else bad "control app does not own the typing engine"; fi

# LaunchAgent lifecycle.
check "grep -q 'agentServiceWithPlistName:kAgentPlist' '$app' && grep -q 'registerAndReturnError' '$app' && grep -q 'unregisterAndReturnError' '$app'" \
      "background-agent lifecycle is owned by SMAppService"
check "grep -q '<key>BundleProgram</key>' '$agent_plist' && grep -q '<string>Contents/Resources/SangKeyAgent</string>' '$agent_plist' && grep -q '<key>KeepAlive</key>' '$agent_plist' && grep -q '<string>Aqua</string>' '$agent_plist'" \
      "bundled LaunchAgent points at the embedded agent"

manual_launchctl=$(grep -R -nE '(^|[^A-Za-z])launchctl([[:space:]]|$)' "$app" "$agent" "$package" "$project" || true)
manual_external_la=$(grep -R -nE '(~|\$HOME|\$\{HOME\})/Library/LaunchAgents|/Users/[^/]+/Library/LaunchAgents|(^|[[:space:]="/])/Library/LaunchAgents' "$app" "$agent" "$package" "$project" || true)
if [ -z "$manual_launchctl" ] && [ -z "$manual_external_la" ]; then ok "runtime/install path never mutates external LaunchAgents or calls launchctl"; else bad "runtime/install path never mutates external LaunchAgents or calls launchctl"; fi

check "grep -q 'SangKeyPreferencesDomain = @\"com.sangtrx.sangkey\"' '$prefs' && grep -q 'CFPreferencesCopyValue' '$prefs' && grep -q 'CFPreferencesSetValue' '$prefs' && grep -q 'CFNotificationCenterGetDarwinNotifyCenter' '$prefs'" \
      "split processes share only explicit preferences + Darwin notification"
check "grep -q '@\"agentDesiredEnabled\": @1' '$prefs' && grep -q 'if (!SangKeyPreferenceBool(kAgentDesiredEnabled)) return;' '$app' && grep -q 'SangKeySetPreferenceBool(kAgentDesiredEnabled, NO)' '$app'" \
      "explicit user disable intent survives control-app relaunch"
check "grep -q '<NSApplicationDelegate, NSMenuDelegate>' '$app' && grep -q 'menuWillOpen:' '$app' && grep -q 'applicationDidBecomeActive:' '$app'" \
      "control UI refreshes externally changed SMAppService status"
check "grep -q 'ScheduleAccessibilityRetry' '$agent' && grep -q 'MIN(delay \* 2.0, 15.0)' '$agent' && ! grep -q 'timerWithTimeInterval:1.0 repeats:YES' '$agent'" \
      "Accessibility retry uses capped exponential backoff"

# Runtime footprint and binary linkage.
check "grep -q 'SANGKEY_AGENT_CI_SMOKE' '$agent' && grep -q 'dictionaries=yes; AppKit=no' '$agent' && grep -q '30720' '$ci'" \
      "CI continuously gates headless runtime footprint"
if grep -Fq 'lipo "$AGENT" -verify_arch arm64 x86_64' "$ci" && \
   grep -Fq 'lipo "$AGENT" -verify_arch arm64 x86_64' "$release"; then
  ok "CI and release require a universal agent"
else
  bad "CI and release require a universal agent"
fi
if grep -Fq 'otool -L "$AGENT"' "$ci" && \
   grep -Fq "grep -Eqi 'AppKit|SwiftUI|Combine|/libswift|ServiceManagement'" "$ci" && \
   grep -Fq "grep -Eqi 'AppKit|SwiftUI|Combine|/libswift|ServiceManagement'" "$release"; then
  ok "dynamic linkage gates forbid heavy runtime frameworks in agent"
else
  bad "dynamic linkage gates forbid heavy runtime frameworks in agent"
fi

# Signing and release supply chain.
check "grep -q 'AGENT_IDENTIFIER=\"com.sangtrx.sangkey.agent\"' '$package' && grep -q 'ACTUAL_AGENT_IDENTIFIER' '$package'" \
      "agent signing identifier is explicit and read back"
check "grep -q 'SANGKEY_REQUIRE_DEVELOPER_ID' '$package' && grep -q 'Developer ID Application:' '$package' && grep -q 'TeamIdentifier' '$package' && grep -q 'DEVELOPER_ID_TEAM_ID' '$release'" \
      "public release requires Developer ID and expected TeamIdentifier"
check "grep -q 'github.ref_protected' '$release' && grep -q 'branches/main' '$release' && grep -q 'main is not protected' '$release'" \
      "release refuses unprotected main/tag provenance"
check "grep -q 'XCODE=/Applications/Xcode_26.6.app' '$ci' && grep -q 'Build version 17F113' '$ci' && grep -q 'XCODE=/Applications/Xcode_26.6.app' '$release' && grep -q 'Build version 17F113' '$release'" \
      "CI and release pin Xcode 26.6 build 17F113"

mutable_uses=$(grep -R -nE '^[[:space:]]*-[[:space:]]+uses:[[:space:]]+[^@]+@[^#[:space:]]+' .github/workflows | grep -vE '@[0-9a-f]{40}([[:space:]]|$)' || true)
if [ -z "$mutable_uses" ]; then ok "GitHub Actions use immutable SHA pins"; else echo "$mutable_uses"; bad "GitHub Actions use immutable SHA pins"; fi
EXPECTED_XCODEGEN_SHA=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
check "grep -q '$EXPECTED_XCODEGEN_SHA' '$ci' && grep -q '$EXPECTED_XCODEGEN_SHA' '$release'" \
      "XcodeGen download is checksum pinned"

build_block=$(awk '/^  build-sign-notarize:/,/^  publish:/' "$release")
publish_block=$(awk '/^  publish:/,0' "$release")
if echo "$build_block" | grep -q 'contents: read' && ! echo "$build_block" | grep -q 'contents: write' && echo "$publish_block" | grep -q 'contents: write' && ! echo "$publish_block" | grep -q 'secrets\.'; then ok "Apple signing secrets stay isolated from repository write permission"; else bad "Apple signing secrets stay isolated from repository write permission"; fi
cleanup_line=$(grep -n -- '- name: Clean up signing material' "$release" | cut -d: -f1)
upload_line=$(grep -n -- '- name: Upload notarized release payload' "$release" | cut -d: -f1)
if [ -n "$cleanup_line" ] && [ -n "$upload_line" ] && [ "$cleanup_line" -lt "$upload_line" ]; then ok "signing material is destroyed before artifact handoff"; else bad "signing material is destroyed before artifact handoff"; fi

check "grep -q 'spctl -a -t open --context context:primary-signature' '$package' && grep -q 'spctl -a -vv --type execute' '$release'" \
      "notarized DMG and mounted app must pass Gatekeeper"
if grep -Fq 'cp "$ROOT/LICENSE" "$DIST/LICENSE.txt"' "$package" && \
   grep -Fq 'cp "$ROOT/NOTICE" "$DIST/NOTICE.txt"' "$package" && \
   grep -Fq 'cp "$ROOT/core/data/ENGLISH_WORDS_PROVENANCE.md" "$DIST/THIRD_PARTY_DATA.txt"' "$package" && \
   grep -q 'Corresponding source for this build' "$package" && \
   grep -q 'build/dist/SOURCE.txt' "$ci"; then
  ok "DMG carries license, notice, third-party provenance and exact corresponding-source pointer"
else
  bad "DMG carries license, notice, third-party provenance and exact corresponding-source pointer"
fi
check "grep -q '/usr/bin/base64 -D' '$release' && grep -q 'Smoke-test release credential decoder' '$ci'" \
      "macOS-native credential decoder is smoke tested"

# English data provenance and generator surface.
if ! grep -Eqi 'english_words\.dat|google-10000|first20hours|add_argument\("--english"' "$gen_dict" && \
   grep -q 'english_common_cc0.json' "$gen_dict" && \
   grep -q 'english_nouns_cc0.json' "$gen_dict" && \
   grep -q 'english_supplement.dat' "$gen_dict" && \
   grep -Fq 'TOKEN_RE = re.compile(rb"[A-Za-z]+")' "$gen_dict"; then
  ok "dictionary generator cannot recreate the removed legacy English payload"
else
  bad "dictionary generator can reintroduce stale English data or tokenization drift"
fi

# Legacy engine provenance/safety.
check "grep -Fq '#define CHR(index) (((index) >= 0 && (index) < MAX_BUFF)' core/engine/DataType.h" \
      "legacy typing-buffer accessor stays bounds checked"
EXPECTED_ENGINE_BLOB=31ed888056436edeb13145c309392b0642f88e7c
if [ "$(git hash-object core/engine/EngineUpstream.inc)" = "$EXPECTED_ENGINE_BLOB" ] && grep -q '#include "EngineUpstream.inc"' core/engine/Engine.cpp && grep -q 'vInputType != vVNI' core/engine/Engine.cpp && grep -q 'dashboard1 ok => dashboard1 ok' core/tests/cases/backspace_restore.txt && grep -q 'expectEq(st, "J7", "a61", "ấ")' core/tests/engine_test.cpp; then ok "legacy engine bytes remain pinned behind Telex/VNI regression gates"; else bad "legacy engine bytes remain pinned behind Telex/VNI regression gates"; fi

check "grep -q 'name: SangKey' '$project' && grep -q 'MARKETING_VERSION: \"0.4.0\"' '$project' && grep -q 'CURRENT_PROJECT_VERSION: \"14\"' '$project' && grep -q 'APP_NAME=\"SangKey\"' '$package'" \
      "product/build identity is SangKey 0.4.0 build 14"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
