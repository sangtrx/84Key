# SangKey

**Ultra-light, Mac-only Vietnamese input for macOS.**

SangKey is a native menu-bar Vietnamese input method designed around the smallest
practical long-running footprint on macOS:

- **Zero Swift / SwiftUI / Combine.** The macOS host is Objective-C++ + AppKit.
- **C++14 typing engine** with Telex, VNI and Simple Telex.
- **Objective-C++ `CGEventTap`** for low-latency system-wide input.
- **One `NSStatusItem` + `NSMenu` at idle.** There is no persistent Settings window.
- **No daemon, XPC helper, ServiceManagement helper, telemetry or background network client.**
- **No embedded auto-updater.** Update checks only open GitHub Releases in the browser.
- **Universal release** (`arm64` + `x86_64`) for macOS 14+.
- **Hardened release chain** with exact-main provenance, ASan/UBSan gates,
  immutable action pins, Developer ID signing and Apple notarization.

## Architecture

```text
AppKit NSStatusItem + NSMenu
           │
           ▼
Objective-C++ SangKey host + InputController
CGEventTap + Accessibility compatibility paths
           │
           ▼
OpenKey-derived C++ engine
Telex / VNI / English detection
```

CI inspects the final Mach-O with `otool -L`; linking Swift, SwiftUI, Combine or
ServiceManagement is a build failure.

## Privacy

All typing conversion happens locally. SangKey has no account system, analytics,
telemetry SDK, clipboard client, keychain client, background updater or in-process
HTTP client.

SangKey needs **System Settings → Privacy & Security → Accessibility** because a
system-wide event-tap input method must observe and synthesize keyboard events.
For password/secure-input contexts, macOS Secure Event Input is the platform
boundary; SangKey does not claim a custom password-field detector.

See [`SECURITY.md`](SECURITY.md) for the full threat model.

## Controls

Everything is intentionally kept in the menu-bar menu rather than a resident
settings UI:

- Vietnamese / English mode.
- Telex, VNI, Simple Telex 1/2.
- Automatic English detection.
- Vietnamese spelling + modern orthography.
- Spotlight and browser/Google Docs compatibility paths.
- Accessibility settings, manual update check, quit.

The VI/EN hotkey defaults to **⌃⌘Space**. SangKey deliberately does not manage
Launch at Login itself; if desired, add SangKey using macOS **System Settings →
General → Login Items**. This keeps ServiceManagement and login-state machinery
out of the always-running keyboard process.

## Install

Releases are published at:

<https://github.com/sangtrx/SangKey/releases>

A release contains:

- `SangKey-vX.Y.Z.dmg`
- `SHA256SUMS`

Verify before installation:

```sh
shasum -a 256 -c SHA256SUMS
xcrun stapler validate SangKey-vX.Y.Z.dmg
```

Then drag **SangKey** into `/Applications`, launch it, and grant Accessibility.
Avoid running another event-based Vietnamese input utility at the same time.

## Build

Requirements:

- macOS 14+
- Xcode 26.x
- XcodeGen 2.46.0

Run the engine/sanitizer/security suite:

```sh
bash core/tests/run_tests.sh
```

Build the app:

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

Create a local package:

```sh
bash tools/package.sh
```

Reproduce the universal release architecture:

```sh
SANGKEY_ARCHS="arm64 x86_64" bash tools/package.sh
```

## Project layout

- `core/engine/` — OpenKey-derived C++ typing engine.
- `core/data/` — English/Vietnamese detection dictionaries.
- `core/tests/` — engine, typing simulation, ASan/UBSan and parser tests.
- `platform/macos/App/SangKeyApp.mm` — complete AppKit menu-bar host.
- `platform/macos/Input/` — Objective-C++ event-tap/input bridge.
- `platform/macos/tests/` — distribution/security/runtime invariants.
- `tools/package.sh` — local/release packaging and notarization.
- `.github/workflows/` — CI and split-privilege release pipeline.

## Lineage and license

SangKey is an independently branded macOS distribution derived from:

- [`nghialuong/84Key`](https://github.com/nghialuong/84Key)
- [`tuyenvm/OpenKey`](https://github.com/tuyenvm/OpenKey)
- [`google-10000-english`](https://github.com/first20hours/google-10000-english)

Upstream attribution is preserved in source files and [`NOTICE`](NOTICE). Because
the typing engine derives from GPLv3-licensed OpenKey, SangKey is distributed
under **GNU GPLv3**. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
