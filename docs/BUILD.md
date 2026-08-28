# Building SangKey

## Prerequisites

- macOS 14+ with **Xcode 26.x** (command-line tools included).
- **XcodeGen 2.46.0** to generate `SangKey.xcodeproj` from
  `platform/macos/project.yml`.
- Python 3 only if you intentionally regenerate dictionaries.

CI does not install XcodeGen through Homebrew. It downloads the exact 2.46.0
release archive and verifies SHA-256 before execution. Local development may use
your preferred installation method, but keep the version aligned with CI.

## Engine tests

The engine is plain C++14 and builds/runs anywhere:

```sh
bash core/tests/run_tests.sh
```

This runs the engine harness, typing simulation, ASan/UBSan parser checks,
send-layer invariants and SangKey distribution/security invariants. It exits
non-zero on any failure and is the same gate used by release preflight.

For fixture-based and live testing details, see [`TESTING.md`](TESTING.md).

## macOS split runtime

SangKey v0.4 builds two products from one Xcode scheme:

```text
SangKey.app
  control menu: AppKit + ServiceManagement
  Contents/Resources/SangKeyAgent
  Contents/Library/LaunchAgents/com.sangtrx.sangkey.agent.plist

SangKeyAgent
  Foundation + ApplicationServices + Carbon + Security
  InputController + C++ engine + dictionaries
  no AppKit / ServiceManagement / Swift
```

Build both:

```sh
cd platform/macos
xcodegen generate
xcodebuild \
  -project SangKey.xcodeproj \
  -scheme SangKey \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

An unsigned Debug build is useful for compile/linkage work, but the hosted CI
intentionally does not exercise real Accessibility or `SMAppService`
registration because those require user-session TCC/background-item approval.
The deterministic CI agent smoke skips only the event tap while loading the real
engine and dictionaries.

## Testing an installed build

For an installed, signed build:

1. Put `SangKey.app` in `/Applications`.
2. Launch it so the control app can register its bundled LaunchAgent using
   `SMAppService`.
3. Approve the background item in **System Settings → General → Login Items** if
   macOS requires approval.
4. Grant **Accessibility** to the SangKey input agent under **Privacy & Security →
   Accessibility**.
5. Close the control app. `SangKeyAgent` should remain running and typing should
   continue.
6. Reopen `SangKey.app` only to change preferences or enable/disable the agent.

Only run one event-based Vietnamese IME at a time. A Debug build and an installed
release use the same LaunchAgent label/agent identity in v0.4, so do **not**
register both simultaneously. Disable/unregister the installed agent before live
Testing a Debug package.

Accessibility persistence depends on stable signed code identity. Release
packaging explicitly signs `SangKeyAgent` with identifier
`com.sangtrx.sangkey.agent`; ad-hoc rebuilds are not a substitute for testing the
real Developer ID artifact before release.

## Dictionaries

`core/data/english_words.dat` and `core/data/viet_telex.dat` are committed.
Regenerate with:

```sh
python3 tools/gen_dict.py
python3 tools/gen_dict.py --english /path/to/google-10000-english.txt
```

The production agent resolves these files beside itself in
`SangKey.app/Contents/Resources`.

## Continuous integration

`.github/workflows/ci.yml` runs two independent jobs on pull requests and `main`:

- Ubuntu: engine, sanitizer and source/security invariants.
- macOS 26: Xcode build, launcher/agent linkage audit, embedded dictionary smoke,
  agent idle-RSS budget, universal `arm64 + x86_64` packaging, nested-code-sign
  identity verification and DMG verification.

The always-on agent must stay below **30 MiB idle RSS** in the deterministic CI
smoke and may not link AppKit, ServiceManagement or Swift runtime machinery.

`.github/workflows/release.yml` runs only on a strict version tag and signs,
notarizes and publishes a universal DMG. See [`RELEASE.md`](RELEASE.md).

## Packaging / distribution

Create a local package:

```sh
bash tools/package.sh
```

Reproduce the universal release architecture:

```sh
SANGKEY_ARCHS="arm64 x86_64" bash tools/package.sh
```

`tools/package.sh` regenerates the Xcode project, builds both products, verifies
the embedded agent + LaunchAgent descriptor, signs the nested agent first with
its explicit code identifier, signs the enclosing app, then creates the DMG.
Without notarization credentials it prints that the local package is not
notarized.

Code signing and notarization require an Apple Developer account. For the
automated Developer ID + notarization release flow, see [`RELEASE.md`](RELEASE.md).
