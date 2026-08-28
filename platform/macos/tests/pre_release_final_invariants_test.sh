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
project=platform/macos/project.yml
readme=README.md
security=SECURITY.md
release_docs=docs/RELEASE.md
changelog=CHANGELOG.md
notice=NOTICE
common=core/data/english_common_cc0.json
nouns=core/data/english_nouns_cc0.json
supplement=core/data/english_supplement.dat
provenance=core/data/ENGLISH_WORDS_PROVENANCE.md
runner=core/tests/run_tests.sh

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
   grep -q 'ENGLISH_WORDS_PROVENANCE.md.*THIRD_PARTY_DATA.txt' "$package" && \
   grep -q 'Corresponding source for this build' "$package" && \
   grep -q 'build/dist/LICENSE.txt' "$ci" && \
   grep -q 'build/dist/THIRD_PARTY_DATA.txt' "$ci" && \
   grep -q 'build/dist/SOURCE.txt' "$ci"; then
  ok "DMG carries license, third-party data provenance, notice, and exact source pointer"
else
  bad "distribution payload is missing license/provenance/source material"
fi

EXPECTED_COMMON_BLOB=8ec4ea53704dfca63f1ee00852c6bcc15411c49e
EXPECTED_NOUNS_BLOB=aca4efb20de9becfd3f949c73e97297be26574f4
EXPECTED_CORPORA_COMMIT=cf30ca27ab176b63623af1ddcfa2447ac07305ba
if [ "$(git hash-object "$common")" = "$EXPECTED_COMMON_BLOB" ] && \
   [ "$(git hash-object "$nouns")" = "$EXPECTED_NOUNS_BLOB" ] && \
   grep -q "$EXPECTED_COMMON_BLOB" "$provenance" && \
   grep -q "$EXPECTED_NOUNS_BLOB" "$provenance" && \
   grep -q "$EXPECTED_CORPORA_COMMIT" "$provenance" && \
   grep -q 'Creative Commons CC0 1.0 Universal' "$provenance" && \
   grep -q "$EXPECTED_COMMON_BLOB" "$notice" && \
   grep -q "$EXPECTED_NOUNS_BLOB" "$notice"; then
  ok "vendored English corpora are byte-pinned to reviewed CC0 upstream data"
else
  bad "English detector corpus provenance/license drifted"
fi

if LC_ALL=C sort -cu "$supplement" >/dev/null 2>&1 && \
   ! grep -nEv '^[a-z]+$' "$supplement" >/dev/null 2>&1 && \
   grep -Fxq 'google' "$supplement" && \
   grep -Fxq 'dashboard' "$supplement" && \
   grep -Fxq 'imagegen' "$supplement" && \
   grep -Fxq 'assign' "$supplement" && \
   grep -Fxq 'search' "$supplement" && \
   grep -Fxq 'your' "$supplement"; then
  ok "SangKey English supplement is deterministic, lowercase, and regression-complete"
else
  bad "English supplement is malformed or missing required regression vocabulary"
fi

if ! git ls-files --error-unmatch core/data/english_words.dat >/dev/null 2>&1 && \
   grep -q 'english_common_cc0.json' "$project" && \
   grep -q 'english_nouns_cc0.json' "$project" && \
   grep -q 'english_supplement.dat' "$project" && \
   ! grep -q 'english_words.dat' "$project" && \
   grep -q 'english_common_cc0.json' "$agent" && \
   grep -q 'english_nouns_cc0.json' "$agent" && \
   grep -q 'english_supplement.dat' "$agent" && \
   ! grep -q 'english_words.dat' "$agent" && \
   ! grep -Eqi 'first20hours|google-10000-english' "$notice"; then
  ok "ambiguously licensed legacy English payload cannot re-enter runtime/release"
else
  bad "legacy English word-list provenance is still reachable by the product"
fi

if grep -q 'PRODUCTION_SIM_LOG' "$runner" && \
   grep -q 'ADVERSARIAL_DICT' "$runner" && \
   grep -q "grep -Ev 'C-prop|C-order'" "$runner" && \
   grep -q 'use_adversarial_dict' "$runner" && \
   grep -q 'typing_sim_test_san' "$runner"; then
  ok "production English behavior and deterministic adversarial compound floors are both gated"
else
  bad "English collision testing can become corpus-dependent or vacuous"
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
