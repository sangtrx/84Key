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

# 10. A tag cannot reach the secret-bearing signing job until a secret-free
#     preflight proves strict semver, exact main HEAD provenance and the full
#     source/security gate. This prevents an accidentally tagged side commit from
#     becoming a perfectly signed malicious or unreviewed binary.
preflight_block=$(awk '/^  preflight:/,/^  build-sign-notarize:/' "$release")
if echo "$preflight_block" | grep -q 'refs/remotes/origin/main' && \
   echo "$preflight_block" | grep -q 'run_tests.sh' && \
   echo "$preflight_block" | grep -q 'MARKETING_VERSION' && \
   echo "$preflight_block" | grep -q 'v\[0-9\].*MINOR.PATCH\|strict semver' && \
   echo "$build_block" | grep -q 'needs: preflight'; then
  ok "release signing is gated by tested exact-main provenance"
else
  bad "release can reach signing without the preflight provenance/test gate"
fi

# 11. AXIsProcessTrusted() can lag after TCC changes. If the event tap actually
#     starts, the UI must treat permission as effective rather than stopping its
#     poll while continuing to display a false missing-permission warning.
refresh_block=$(awk '/func refresh\(\) -> Bool/,/^    }/' platform/macos/App/AppController.swift)
if echo "$refresh_block" | grep -Fq 'hasPermission = running || input.hasAccessibilityPermission()'; then
  ok "a live event tap is treated as effective Accessibility permission"
else
  bad "permission UI can disagree with a successfully running event tap"
fi

# 12. The hardened app must identify this fork as its auditable source while
#     preserving upstream credit separately. Update navigation already targets
#     this fork; About must not send a security-conscious user to the wrong tree.
about=platform/macos/App/Settings/SettingsSections.swift
if grep -q 'github.com/sangtrx/84Key' "$about" && \
   grep -q 'Dự án 84Key gốc' "$about" && \
   grep -q 'github.com/nghialuong/84Key' "$about"; then
  ok "About links the hardened source and preserves upstream provenance"
else
  bad "About does not clearly distinguish hardened source from upstream"
fi

# 13. Public release artifacts are universal; otherwise an arm64 GitHub runner
#     silently turns the documented macOS 14+ release into Apple-Silicon-only.
if grep -q "KEY84_ARCHS: 'arm64 x86_64'" .github/workflows/ci.yml && \
   grep -q "KEY84_ARCHS: 'arm64 x86_64'" "$release" && \
   grep -q 'lipo -verify_arch arm64 x86_64' .github/workflows/ci.yml && \
   grep -q 'lipo -verify_arch arm64 x86_64' "$release"; then
  ok "CI and release require universal arm64+x86_64 artifacts"
else
  bad "release architecture is not explicitly universal and verified"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
