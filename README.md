# SangKey

**Ultra-light, Mac-only Vietnamese input for macOS.**

SangKey is a native Vietnamese input method designed so the process that handles
keystrokes 24/7 stays as small as practical:

- **Headless `SangKeyAgent`.** The always-on input process does not link AppKit,
  ServiceManagement, Swift, SwiftUI or Combine.
- **Ephemeral control app.** `SangKey.app` uses AppKit + ServiceManagement only
  while you are changing settings or managing the background agent; you can close
  it and typing continues.
- **C++14 typing engine** with Telex, VNI and Simple Telex.
- **Objective-C++ `CGEventTap`** for low-latency system-wide input.
- **No XPC service, daemon, telemetry or background network client.** The helper
  is a user-session LaunchAgent bundled inside the app and registered with Apple's
  `SMAppService` API.
- **No embedded auto-updater.** Update checks only open GitHub Releases in the browser.
- **Universal release** (`arm64` + `x86_64`) for macOS 14+.
- **Hardened release chain** with exact-main provenance, ASan/UBSan gates,
  immutable action pins, Developer ID signing and Apple notarization.

## Architecture

```text
SangKey.app — opened only when needed
AppKit control menu + ServiceManagement
              │
              │ CFPreferences + Darwin notification
              ▼
SangKeyAgent — always running
Foundation + ApplicationServices + Carbon + Security
CGEventTap + Accessibility compatibility paths
              │
              ▼
OpenKey-derived C++ engine
Telex / VNI / English detection
```

The control app and input agent share an explicit preferences domain. There is no
XPC protocol or database between them. CI inspects both final Mach-O binaries;
the always-on agent fails the build if it links AppKit, ServiceManagement,
SwiftUI, Combine or the Swift runtime.

## Footprint

The v0.4 CI gate runs the **actual embedded SangKeyAgent** with both English and
Vietnamese dictionaries loaded, while skipping only the TCC-dependent event tap.
Its idle RSS must stay below **30 MiB**. The architecture was selected after
measurement showed the previous AppKit-resident process dominated idle memory;
rewriting the dictionaries would have saved very little by comparison.

## Privacy

All typing conversion happens locally. SangKey has no account system, analytics,
telemetry SDK, clipboard client, keychain client, background updater or in-process
HTTP client in the input agent.

`SangKeyAgent` needs **System Settings → Privacy & Security → Accessibility**
because a system-wide event-tap input method must observe and synthesize keyboard
events. For password/secure-input contexts, macOS Secure Event Input is the
platform boundary; SangKey does not claim a custom password-field detector.

The control app itself does not process keystrokes. It can open the Accessibility
and Login Items settings pages so you can approve the agent when macOS requires it.

See [`SECURITY.md`](SECURITY.md) for the full threat model.

## Controls

Launch **SangKey.app** when you want to change settings. Its transient menu lets
you:

- enable/disable the background input agent;
- select Vietnamese / English mode;
- select Telex, VNI, Simple Telex 1/2;
- toggle automatic English detection;
- toggle Vietnamese spelling + modern orthography;
- toggle Spotlight and browser/Google Docs compatibility paths;
- open Accessibility or Login Items settings;
- open the GitHub Releases page for a manual update check.

The VI/EN hotkey defaults to **⌃⌘Space**. Choosing **Đóng bảng điều khiển** exits
the AppKit control process; the registered `SangKeyAgent` continues running.
Choosing **Tắt bộ gõ nền** persists that choice, so reopening the control app does
not silently re-enable it.

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

Then:

1. Drag **SangKey** into `/Applications`.
2. Launch `SangKey.app` once so it can register the bundled background agent.
3. If macOS asks for background-item approval, use **Mở Login Items…** and approve it.
4. Grant **Accessibility** to the SangKey input agent when macOS prompts / shows it
   in Privacy & Security → Accessibility.
5. Close the control panel when finished; the headless agent keeps typing.

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

Build the app + agent:

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
- `platform/macos/Agent/` — always-on headless `SangKeyAgent` + bundled LaunchAgent descriptor.
- `platform/macos/App/SangKeyApp.mm` — ephemeral AppKit/ServiceManagement control menu.
- `platform/macos/HeadlessCompat/` — narrow adapters for three AppKit conveniences inherited by the input bridge.
- `platform/macos/Shared/` — explicit shared preferences + Darwin notification contract.
- `platform/macos/Input/` — Objective-C++ event-tap/input bridge.
- `platform/macos/tests/` — distribution/security/runtime invariants.
- `tools/package.sh` — nested-code signing, local/release packaging and notarization.
- `.github/workflows/` — CI and split-privilege release pipeline.

## Lineage and license

SangKey is an independently branded macOS distribution derived from:

- [`nghialuong/84Key`](https://github.com/nghialuong/84Key)
- [`tuyenvm/OpenKey`](https://github.com/tuyenvm/OpenKey)
- [`google-10000-english`](https://github.com/first20hours/google-10000-english)

Upstream attribution is preserved in source files and [`NOTICE`](NOTICE). Because
the typing engine derives from GPLv3-licensed OpenKey, SangKey is distributed
under **GNU GPLv3**. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
