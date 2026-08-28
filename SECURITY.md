# Security Policy

## Supported versions

Security fixes are provided for the latest SangKey release line.

| Version | Supported |
|---------|-----------|
| 0.3.x   | ✅        |
| 0.2.x   | ❌ pre-SangKey migration |
| 0.1.x   | ❌ upstream baseline only |

## Reporting a vulnerability

Please report security issues privately through GitHub Security Advisories:
<https://github.com/sangtrx/SangKey/security/advisories/new>

Include reproduction steps, affected version/commit, and macOS version.

## Threat model and privacy

SangKey requires macOS **Accessibility** permission because it implements a
session-level `CGEvent` tap and, for selected system search fields, uses the
Accessibility API to read/replace the focused field locally. This is inherently a
powerful permission, so the runtime and distribution chain are intentionally kept
small and auditable.

Runtime constraints:

- Typing conversion stays **local on the Mac**.
- The always-running host is **Objective-C++ + AppKit + the C++ engine**. There is
  no Swift, SwiftUI, Combine, ServiceManagement, daemon or XPC helper.
- There is **no embedded updater** or background network client. The update menu
  item only opens the SangKey GitHub Releases page after an explicit click.
- There is no clipboard client, keychain client, telemetry, analytics SDK or
  typing-data upload path.
- The inherited `KEY84_TRACE` path is scrubbed before input interception begins.
- macOS **Secure Event Input** is the platform boundary for secure/password input;
  SangKey does not claim to implement its own password-field detector.
- Serialized legacy parsers fail closed on malformed/truncated input and are
  covered by ASan/UBSan.
- Release and debug bundle identifiers are `com.sangtrx.sangkey` and
  `com.sangtrx.sangkey.debug`, keeping TCC/code-sign provenance independent from
  upstream 84Key.

## Lightweight-runtime gate

CI inspects the final Mach-O using `otool -L`. A build fails if the shipping
binary links Swift/SwiftUI/Combine or ServiceManagement. The source invariant
also requires the macOS app host to contain no Swift files and no retained
settings/onboarding view hierarchy.

## Distribution hardening

The release workflow separates privileges:

- secret-free preflight requires strict semver on the exact current `main`, checks
  source version, and reruns the complete core/security suite;
- build/sign/notarize has repository read-only permission plus protected Apple
  signing/notarization secrets;
- publish has `contents: write` but no Apple secrets;
- reusable GitHub Actions are pinned to immutable commit SHAs;
- XcodeGen 2.46.0 is SHA-256 verified before execution;
- signing material is destroyed before artifact handoff;
- each release publishes a notarized universal (`arm64` + `x86_64`) DMG together
  with `SHA256SUMS`.

Apple notarization and Developer ID signing are additional distribution checks,
not substitutes for source review.
