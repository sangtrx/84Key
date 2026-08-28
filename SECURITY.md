# Security Policy

## Supported versions

Security fixes are provided for the latest SangKey release line.

| Version | Supported |
|---------|-----------|
| 0.4.x   | ✅        |
| 0.3.x   | ❌ superseded by split-runtime architecture |
| 0.2.x   | ❌ pre-SangKey migration |
| 0.1.x   | ❌ upstream baseline only |

## Reporting a vulnerability

Please report security issues privately through GitHub Security Advisories:
<https://github.com/sangtrx/SangKey/security/advisories/new>

Include reproduction steps, affected version/commit, and macOS version.

## Threat model and privacy

`SangKeyAgent` requires macOS **Accessibility** permission because it implements a
session-level `CGEvent` tap and, for selected system search fields, uses the
Accessibility API to read/replace the focused field locally. This is inherently a
powerful permission, so the always-on process and distribution chain are kept as
small and auditable as practical.

Runtime constraints:

- Typing conversion stays **local on the Mac**.
- The always-running process is a headless Objective-C++/C++ `SangKeyAgent` that
  links Foundation, ApplicationServices, Carbon and Security. It does **not** link
  AppKit, ServiceManagement, Swift, SwiftUI or Combine.
- `SangKey.app` is an ephemeral AppKit + ServiceManagement control surface. It
  does not contain the typing engine or event tap and may be closed while the
  input agent continues running.
- The background helper is a user-session LaunchAgent bundled under
  `SangKey.app/Contents/Library/LaunchAgents` and registered with `SMAppService`.
  SangKey does not write `~/Library/LaunchAgents` and does not shell out to
  `launchctl`.
- Launcher and agent share only an explicit `com.sangtrx.sangkey` CFPreferences
  domain plus a Darwin notification. There is no XPC service or local database.
- There is **no embedded updater** or background network client. The update menu
  item only opens the SangKey GitHub Releases page after an explicit click.
- There is no clipboard client, keychain client, telemetry, analytics SDK or
  typing-data upload path in the always-on process.
- The inherited `KEY84_TRACE` path is scrubbed before input interception begins.
- macOS **Secure Event Input** is the platform boundary for secure/password input;
  SangKey does not claim to implement its own password-field detector.
- Serialized legacy parsers fail closed on malformed/truncated input and are
  covered by ASan/UBSan.

## Code identity and TCC

The application identities are intentionally independent from upstream 84Key:

- release control app: `com.sangtrx.sangkey`
- debug control app: `com.sangtrx.sangkey.debug`
- headless input agent: `com.sangtrx.sangkey.agent`

The agent is a command-line Mach-O rather than an application bundle, so release
packaging pins its **code-signing identifier explicitly** to
`com.sangtrx.sangkey.agent` before signing the enclosing app. CI and release read
that identifier back from the signature and fail if it drifts. This keeps the
agent's designated requirement / permission identity deterministic across builds.

## Lightweight-runtime gate

CI inspects both final Mach-O binaries using `otool -L`:

- the transient launcher is allowed AppKit + ServiceManagement but not Swift;
- the always-on agent fails if it links AppKit, ServiceManagement, SwiftUI,
  Combine or the Swift runtime.

The CI smoke runs the actual embedded agent with both production dictionaries
loaded while skipping only the TCC-dependent event tap. Idle RSS must remain
below **30 MiB**, and CPU is reported for every macOS build.

## Distribution hardening

The release workflow separates privileges:

- secret-free preflight requires strict semver on the exact current `main`, checks
  source version, and reruns the complete core/security suite;
- build/sign/notarize has repository read-only permission plus protected Apple
  signing/notarization secrets;
- the nested `SangKeyAgent` is signed first with its explicit identifier and
  Hardened Runtime, then the enclosing app is signed and deep-verified;
- publish has `contents: write` but no Apple secrets;
- reusable GitHub Actions are pinned to immutable commit SHAs;
- XcodeGen 2.46.0 is SHA-256 verified before execution;
- signing material is destroyed before artifact handoff;
- each release publishes a notarized universal (`arm64` + `x86_64`) launcher and
  agent inside the DMG together with `SHA256SUMS`.

Apple notarization and Developer ID signing are additional distribution checks,
not substitutes for source review.
