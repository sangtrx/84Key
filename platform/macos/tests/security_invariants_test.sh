#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
pass=0
fail=0
ok()  { echo "  [PASS] $1"; pass=$((pass + 1)); }
bad() { echo "  [FAIL] $1"; fail=$((fail + 1)); }

echo "== SangKey distribution + lightweight runtime invariants =="

if grep -R -n -E 'import Sparkle|package: Sparkle|SUFeedURL|SUPublicEDKey|SPUStandardUpdaterController' \
    platform/macos/project.yml platform/macos/Resources/Info.plist \
    platform/macos/App/UpdaterController.swift tools/package.sh .github/workflows/release.yml >/dev/null 2>&1; then
  bad "embedded updater references are present"
else
  ok "no embedded auto-updater/appcast runtime"
fi

if grep -q 'NSWorkspace.shared.open' platform/macos/App/UpdaterController.swift && \
   ! grep -qE 'URLSession|URLRequest|downloadTask|dataTask|Process\(|NSTask|curl|wget' platform/macos/App/UpdaterController.swift; then
  ok "update check is browser navigation only"
else
  bad "update controller gained network/download execution"
fi

runtime_sensitive=$(grep -nE \
  'URLSession|URLRequest|NSURLConnection|NWConnection|CFStream(Create|Open)|socket\(|NSPasteboard|SecItem(CopyMatching|Add|Update|Delete)' \
  platform/macos/App/AppDelegate.swift platform/macos/App/AppController.swift \
  platform/macos/App/AppSettings.swift platform/macos/App/StatusMenuController.swift \
  platform/macos/App/SettingsWindowController.swift platform/macos/App/UpdaterController.swift \
  platform/macos/Input/InputController.mm || true)
if [ -z "$runtime_sensitive" ]; then ok "runtime has no direct network/clipboard/Keychain client"; else echo "$runtime_sensitive"; bad "sensitive runtime API added"; fi

if awk '/func startup\(\)/,/loadDictionaries/' platform/macos/App/AppController.swift | grep -q 'unsetenv("KEY84_TRACE")'; then
  ok "diagnostic key trace is scrubbed before interception"
else
  bad "KEY84_TRACE can reach the hardened runtime"
fi

if grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.sangtrx.sangkey$' platform/macos/project.yml && \
   grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.sangtrx.sangkey.debug$' platform/macos/project.yml; then
  ok "SangKey uses independent TCC/code-sign identities"
else
  bad "SangKey bundle identity is not isolated"
fi

active_swift=(
  platform/macos/App/AppDelegate.swift
  platform/macos/App/AppController.swift
  platform/macos/App/AppSettings.swift
  platform/macos/App/LoginItemManager.swift
  platform/macos/App/StatusMenuController.swift
  platform/macos/App/SettingsWindowController.swift
  platform/macos/App/UpdaterController.swift
)
if ! grep -nE '^import (SwiftUI|Combine)$' "${active_swift[@]}" >/dev/null && \
   grep -q -- '- Key84App.swift' platform/macos/project.yml && \
   grep -q -- '- Settings' platform/macos/project.yml && \
   grep -q -- '- DesignSystem' platform/macos/project.yml; then
  ok "shipping Swift layer is AppKit-only with no SwiftUI/Combine"
else
  bad "SwiftUI/Combine can enter the shipping compile graph"
fi

mutable_uses=$(grep -R -nE '^[[:space:]]*-[[:space:]]+uses:[[:space:]]+[^@]+@[^#[:space:]]+' .github/workflows \
  | grep -vE '@[0-9a-f]{40}([[:space:]]|$)' || true)
if [ -z "$mutable_uses" ]; then ok "GitHub Actions are immutable-SHA pinned"; else echo "$mutable_uses"; bad "mutable GitHub Action ref"; fi

EXPECTED_XCODEGEN_SHA=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
if grep -q "$EXPECTED_XCODEGEN_SHA" .github/workflows/ci.yml && grep -q "$EXPECTED_XCODEGEN_SHA" .github/workflows/release.yml; then
  ok "XcodeGen is checksum pinned"
else
  bad "XcodeGen dependency is not deterministic"
fi

release=.github/workflows/release.yml
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

refresh_block=$(awk '/func refresh\(\) -> Bool/,/^    }/' platform/macos/App/AppController.swift)
if echo "$refresh_block" | grep -Fq 'hasPermission = running || input.hasAccessibilityPermission()'; then
  ok "live event tap counts as effective Accessibility permission"
else
  bad "permission UI can disagree with the event tap"
fi

if grep -q 'github.com/sangtrx/SangKey/releases/latest' platform/macos/App/UpdaterController.swift && \
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

if grep -q 'static func sync(enabled: Bool) -> Bool' platform/macos/App/LoginItemManager.swift && \
   grep -q 'setRunOnStartup' platform/macos/App/AppSettings.swift && \
   grep -q 'reconcileRunOnStartup' platform/macos/App/AppController.swift; then
  ok "Run at Login follows effective SMAppService state without Combine"
else
  bad "Run at Login state can drift from macOS"
fi

if grep -q 'let alert = NSAlert()' platform/macos/App/AppController.swift && \
   grep -q -- '- OnboardingView.swift' platform/macos/project.yml; then
  ok "first-run permission UI is non-retained AppKit, not a SwiftUI tree"
else
  bad "onboarding can keep heavyweight UI alive"
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

if grep -q 'name: SangKey' platform/macos/project.yml && \
   grep -q 'MARKETING_VERSION: "0.3.0"' platform/macos/project.yml && \
   grep -q 'APP_NAME="SangKey"' tools/package.sh; then
  ok "product/build identity is consistently SangKey 0.3.0"
else
  bad "product identity is mixed between 84Key and SangKey"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
