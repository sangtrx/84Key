# Security Policy

## Supported versions

Security fixes are provided for the latest hardened fork release line.

| Version | Supported |
|---------|-----------|
| 0.2.x   | ✅        |
| 0.1.x   | ❌ upstream baseline only |
| < 0.1   | ❌        |

## Reporting a vulnerability

Please report security issues **privately** rather than opening a public issue.
Use GitHub Security Advisories for this fork:
<https://github.com/sangtrx/84Key/security/advisories/new>

Include a description, reproduction steps, the affected version/commit, and the
macOS version. Coordinated disclosure is appreciated.

## Threat model and privacy

84Key requires macOS **Accessibility** permission because it implements a
session-level `CGEvent` tap and, for specific system search fields, uses the
Accessibility API to read/replace the focused field locally. That is a powerful
permission: the process has the technical capability to observe normal keyboard
events delivered to its event tap, so the source and distribution chain should
be treated with the same care as other input software.

The hardened fork is designed around the following constraints:

- Typing conversion happens **locally on the Mac**. There is no telemetry,
  analytics SDK, account system, or typing-data upload path.
- There is **no embedded auto-updater**. The menu's update command only opens
  this fork's GitHub Releases page in the default browser after an explicit user
  action. The app does not download or install executable updates itself.
- The inherited `KEY84_TRACE` diagnostic path is forcibly disabled at startup
  before input interception begins, so release users cannot enable per-key
  diagnostic logging through an environment variable.
- macOS **Secure Event Input** is the platform boundary for password/secure-input
  contexts: the event-tap mechanism is restricted by the OS while secure input
  is active. We do not claim a separate password-field detector implemented by
  84Key itself.
- The serialized macro and smart-switch parsers fail closed on truncated length
  fields and are exercised under ASan/UBSan in CI.
- This fork uses `com.sangtrx.key84` (and a separate debug bundle id) instead of
  reusing upstream's bundle identity, keeping code-sign/TCC provenance distinct.

## Distribution hardening

The release workflow intentionally separates privileges:

- build/sign/notarize has repository **read-only** permission and access to the
  protected Apple signing/notarization secrets;
- publish has `contents: write` but **no Apple secrets**;
- reusable GitHub Actions are pinned to immutable commit SHAs;
- XcodeGen is pinned to version 2.46.0 and its release archive is SHA-256 checked
  before execution;
- each release publishes the notarized DMG together with `SHA256SUMS`.

Apple notarization and Developer ID signing are additional distribution checks,
not substitutes for source review. CI also enforces source-level security
invariants so reintroducing an embedded updater, mutable Actions refs, or the
upstream bundle identity fails the test suite.
