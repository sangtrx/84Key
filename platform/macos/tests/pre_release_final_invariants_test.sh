#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
pass=0
fail=0
ok()  { echo "  [PASS] $1"; pass=$((pass + 1)); }
bad() { echo "  [FAIL] $1"; fail=$((fail + 1)); }

echo "== SangKey final pre-release invariants =="

app=platform/macos/App/SangKeyApp.mm
agent=platform/macos/Agent/SangKeyAgent.mm
ci=.github/workflows/ci.yml
release=.github/workflows/release.yml
package=tools/package.sh
readme=README.md
security=SECURITY.md
release_docs=docs/RELEASE.md
changelog=CHANGELOG.md

if grep -q 'kRepoReleases = @"https://github.com/sangtrx/84Key/releases/latest"' "$app" && \
   grep -q 'Planned canonical post-rename path: https://github.com/sangtrx/SangKey/releases/latest' "$app"; then
  ok "manual update URL resolves before and after the planned repository rename"
else
  bad "manual update URL can point at a repository that does not exist"
fi

if grep -q '<NSApplicationDelegate, NSMenuDelegate>' "$app" && \
   grep -q 'menuWillOpen:' "$app" && \
   grep -q 'applicationDidBecomeActive:' "$app"; then
  ok "control menu refreshes external SMAppService status changes"
else
  bad "background-agent status can remain stale after System Settings changes"
fi

if grep -q 'ScheduleAccessibilityRetry' "$agent" && \
   grep -q 'MIN(delay \* 2.0, 15.0)' "$agent" && \
   ! grep -q 'timerWithTimeInterval:1.0 repeats:YES' "$agent"; then
  ok "Accessibility retry uses bounded exponential backoff"
else
  bad "Accessibility retry can wake the agent every second indefinitely"
fi

if grep -q 'XCODE=/Applications/Xcode_26.6.app' "$ci" && \
   grep -q 'Build version 17F113' "$ci" && \
   grep -q 'XCODE=/Applications/Xcode_26.6.app' "$release" && \
   grep -q 'Build version 17F113' "$release"; then
  ok "CI and release pin exact Xcode 26.6 build 17F113"
else
  bad "macOS toolchain can drift without a reviewed source change"
fi

if grep -q 'SANGKEY_REQUIRE_DEVELOPER_ID' "$package" && \
   grep -q 'Developer ID Application:' "$package" && \
   grep -q 'TeamIdentifier' "$package" && \
   grep -q 'DEVELOPER_ID_TEAM_ID' "$release"; then
  ok "release requires Developer ID and verifies the expected TeamIdentifier"
else
  bad "release signer identity is not fail-closed"
fi

if grep -q 'github.ref_protected' "$release" && \
   grep -q 'branches/main' "$release" && \
   grep -q 'main is not protected' "$release"; then
  ok "release refuses unprotected tag/main provenance"
else
  bad "release can sign from unprotected Git refs"
fi

if [ "$(grep -c '^[[:space:]]*environment: release$' "$release")" -ge 2 ] && \
   grep -q 'test that exact DMG on' "$release"; then
  ok "signed artifact requires a second protected-environment approval before publish"
else
  bad "public publish lacks a post-build human acceptance gate"
fi

if grep -q 'spctl -a -t open --context context:primary-signature' "$package" && \
   grep -q 'spctl -a -vv --type execute' "$release"; then
  ok "notarized DMG and mounted app must pass Gatekeeper assessment"
else
  bad "release can publish without Gatekeeper assessment"
fi

if grep -q 'cp "$ROOT/LICENSE" "$DIST/LICENSE.txt"' "$package" && \
   grep -q 'cp "$ROOT/NOTICE" "$DIST/NOTICE.txt"' "$package" && \
   grep -q 'Corresponding source for this build' "$package" && \
   grep -q 'build/dist/LICENSE.txt' "$ci" && \
   grep -q 'build/dist/SOURCE.txt' "$ci"; then
  ok "DMG carries license, notice, and exact corresponding-source pointer"
else
  bad "GPL distribution payload is missing provenance/source material"
fi

if grep -q 'github.com/sangtrx/84Key/releases' "$readme" && \
   grep -q 'github.com/sangtrx/84Key/security/advisories/new' "$security" && \
   grep -q 'github.com/sangtrx/84Key/releases/latest' "$release_docs"; then
  ok "public documentation points at the live repository before rename"
else
  bad "public documentation contains pre-rename 404 repository links"
fi

if grep -q '^## \[0.4.0\] - 2026-08-28' "$changelog" && \
   grep -q '^## \[0.3.0\] - 2026-08-28' "$changelog"; then
  ok "SangKey 0.3/0.4 release history is documented"
else
  bad "changelog does not describe the SangKey architecture releases"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
