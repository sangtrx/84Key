#!/bin/bash
# Source-level security invariants for the hardened macOS distribution.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

pass=0
fail=0
ok()  { echo "  [PASS] $1"; pass=$((pass + 1)); }
bad() { echo "  [FAIL] $1"; fail=$((fail + 1)); }

echo "== hardened distribution security invariants =="

# 1. No embedded auto-updater / installer framework or appcast configuration.
if grep -R -n -E 'import Sparkle|package: Sparkle|SUFeedURL|SUPublicEDKey|SPUStandardUpdaterController' \
    platform/macos/project.yml \
    platform/macos/Resources/Info.plist \
    platform/macos/App/UpdaterController.swift \
    tools/package.sh \
    .github/workflows/release.yml >/dev/null 2>&1; then
  bad "auto-updater/install-helper references are present"
else
  ok "no embedded auto-updater or appcast configuration"
fi

# 2. The user-visible update action may navigate to Releases, but it must not
#    become a hidden network client or code downloader.
if grep -q 'NSWorkspace.shared.open' platform/macos/App/UpdaterController.swift && \
   ! grep -qE 'URLSession|URLRequest|downloadTask|dataTask|Process\(|NSTask|curl|wget' \
      platform/macos/App/UpdaterController.swift; then
  ok "update check is a user-initiated browser navigation only"
else
  bad "update controller gained an in-process network/download execution path"
fi

# 3. No general-purpose network/credential/clipboard client may silently appear
#    in the Accessibility-enabled runtime. Opening a URL through NSWorkspace is
#    intentionally outside these patterns and remains user initiated.
runtime_sensitive=$(grep -R -nE \
  'URLSession|URLRequest|NSURLConnection|NWConnection|CFStream(Create|Open)|socket\(|NSPasteboard|SecItem(CopyMatching|Add|Update|Delete)' \
  platform/macos/App platform/macos/Input || true)
if [ -z "$runtime_sensitive" ]; then
  ok "runtime has no direct network, clipboard, or Keychain client"
else
  echo "$runtime_sensitive"
  bad "sensitive runtime API added without threat-model review"
fi

# 4. Upstream diagnostic tracing must be scrubbed before the event tap starts.
if awk '/func startup\(\)/,/refresh\(\)/' platform/macos/App/AppController.swift \
     | grep -q 'unsetenv("KEY84_TRACE")'; then
  ok "KEY84_TRACE is scrubbed before input interception starts"
else
  bad "KEY84_TRACE can be enabled in the hardened application"
fi

# 5. Fork identity must not reuse upstream's TCC/code-sign identity.
if grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.sangtrx.key84$' platform/macos/project.yml && \
   grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.sangtrx.key84.debug$' platform/macos/project.yml && \
   ! grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.nghialuong.key84' platform/macos/project.yml; then
  ok "release and debug builds use fork-specific bundle identities"
else
  bad "bundle identity can collide with upstream 84Key"
fi

# 6. GitHub Actions must be immutable-SHA pinned. A mutable @vN tag on code that
#    receives repository or artifact permissions is a supply-chain regression.
mutable_uses=$(grep -R -nE '^[[:space:]]*-[[:space:]]+uses:[[:space:]]+[^@]+@[^#[:space:]]+' .github/workflows \
  | grep -vE '@[0-9a-f]{40}([[:space:]]|$)' || true)
if [ -z "$mutable_uses" ]; then
  ok "all reusable GitHub Actions are pinned to full commit SHAs"
else
  echo "$mutable_uses"
  bad "one or more GitHub Actions use mutable refs"
fi

# 7. Release/build jobs execute only the checksum-pinned XcodeGen archive, not a
#    mutable Homebrew formula in the signing environment.
EXPECTED_XCODEGEN_SHA=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
if grep -q "$EXPECTED_XCODEGEN_SHA" .github/workflows/ci.yml && \
   grep -q "$EXPECTED_XCODEGEN_SHA" .github/workflows/release.yml && \
   ! grep -R -q 'brew install xcodegen' .github/workflows; then
  ok "XcodeGen is version/checksum pinned in CI and release"
else
  bad "XcodeGen build dependency is not deterministically verified"
fi

# 8. Signing credentials and contents:write must not coexist in one job.
release=.github/workflows/release.yml
build_block=$(awk '/^  build-sign-notarize:/,/^  publish:/' "$release")
publish_block=$(awk '/^  publish:/,0' "$release")
if echo "$build_block" | grep -q 'contents: read' && \
   ! echo "$build_block" | grep -q 'contents: write' && \
   echo "$publish_block" | grep -q 'contents: write' && \
   ! echo "$publish_block" | grep -q 'secrets\.'; then
  ok "signing secrets are isolated from the release write token"
else
  bad "release workflow mixes signing secrets with repository write permission"
fi

# 9. Apple credentials must be deleted before the artifact helper executes.
cleanup_line=$(grep -n -- '- name: Clean up signing material' "$release" | cut -d: -f1)
upload_line=$(grep -n -- '- name: Upload notarized release payload' "$release" | cut -d: -f1)
if [ -n "$cleanup_line" ] && [ -n "$upload_line" ] && [ "$cleanup_line" -lt "$upload_line" ]; then
  ok "signing material is destroyed before artifact handoff"
else
  bad "artifact helper can run while Apple signing material still exists"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
