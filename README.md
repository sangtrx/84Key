# 84Key — hardened macOS fork

![84Key — Bộ gõ tiếng Việt cho macOS](docs/assets/banner.png)

![License: GPLv3](https://img.shields.io/badge/License-GPLv3-blue.svg)

A free, open-source Vietnamese input method for macOS, forked from
[`nghialuong/84Key`](https://github.com/nghialuong/84Key) and hardened for use on
machines where keyboard-input software should have the smallest practical attack
surface.

84Key uses the OpenKey C++ Vietnamese typing engine and a native SwiftUI menu-bar
host. It supports **Telex, VNI and Simple Telex**, Unicode and legacy code tables,
automatic English-word detection, and compatibility fixes for Spotlight and web
editors.

## Why this fork exists

A Vietnamese input method using a session-level macOS event tap necessarily
receives a powerful **Accessibility** permission. The hardened fork therefore
removes components that are useful for convenience but unnecessary for typing:

- **No embedded auto-updater or installer helper.** Sparkle is not linked or
  shipped. There is no appcast and no background update check.
- **No typing telemetry or analytics.** Typing conversion stays on-device.
- **Manual update check only.** *Kiểm tra cập nhật…* opens this fork's GitHub
  Releases page in the default browser after you click it.
- **Keystroke trace disabled.** The inherited `KEY84_TRACE` diagnostic switch is
  scrubbed before input interception starts.
- **Parser hardening.** Legacy macro/smart-switch binary parsers bounds-check all
  length-prefixed fields and run under ASan/UBSan regression tests.
- **Separate app identity.** Release bundle id is `com.sangtrx.key84`; debug is
  `com.sangtrx.key84.debug`, avoiding TCC/code-sign identity collisions with the
  upstream application.
- **Hardened release chain.** GitHub Actions are immutable-SHA pinned; XcodeGen is
  exact-version/SHA-256 verified; signing secrets are isolated from the job that
  has repository write permission; releases include `SHA256SUMS`.

See [`SECURITY.md`](SECURITY.md) for the threat model and
[`docs/RELEASE.md`](docs/RELEASE.md) for the release security design.

## Privacy and permissions

All Vietnamese conversion happens locally. The app has no account system,
telemetry SDK, analytics endpoint, or in-process update downloader.

84Key needs **System Settings → Privacy & Security → Accessibility** because it
uses a `CGEvent` tap to transform keystrokes and the Accessibility API for a
small number of focused-field compatibility fixes. This is inherently a strong
permission; review the source and install only builds whose provenance you trust.

For password/secure-input contexts, **macOS Secure Event Input** is the platform
boundary that restricts event-tap delivery. This fork does not claim to implement
its own password-field detector.

## Features

- Telex, VNI and Simple Telex input methods.
- Unicode by default; TCVN3, VNI-Windows, Unicode Compound and CP1258 available.
- Modern Vietnamese orthography and spelling checks.
- Automatic English-word detection for mixed Vietnamese/English typing.
- Spotlight/system-search compatibility handling.
- Chromium/web-editor compatibility handling.
- Native menu-bar UI with configurable VI/EN switch shortcut.
- Optional launch at login through Apple's `SMAppService`.

## Install

Download a release from:

<https://github.com/sangtrx/84Key/releases>

A public release should contain:

- `84Key-vX.Y.Z.dmg`
- `SHA256SUMS`

Verify the checksum before installation:

```sh
shasum -a 256 -c SHA256SUMS
```

For a signed release you can additionally check Gatekeeper/notarization:

```sh
xcrun stapler validate 84Key-vX.Y.Z.dmg
spctl -a -t open --context context:primary-signature 84Key-vX.Y.Z.dmg
```

Then open the DMG, drag **84Key** into `/Applications`, launch it, and grant
Accessibility when macOS prompts. Disable other Vietnamese IMEs while using 84Key
because two event-based input methods can conflict.

There is deliberately no automatic installation of future releases. The menu's
*Kiểm tra cập nhật…* command only opens the Releases page.

## Build from source

Requirements:

- macOS 14+
- Xcode 26.x for the same SDK family used by CI/release
- XcodeGen 2.46.0

Run the C++ engine, parser sanitizer and source-security tests:

```sh
bash core/tests/run_tests.sh
```

Generate and build the macOS app:

```sh
cd platform/macos
xcodegen generate
xcodebuild \
  -project 84Key.xcodeproj \
  -scheme 84Key \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Package locally from the repository root:

```sh
bash tools/package.sh
```

`tools/package.sh` regenerates the Xcode project from `platform/macos/project.yml`
before building so the generated project cannot silently retain removed package
dependencies.

CI does not execute a mutable Homebrew XcodeGen formula: it downloads the exact
2.46.0 release archive and verifies SHA-256
`4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`
before execution.

## Project layout

- `core/engine/` — OpenKey-derived C++ typing engine.
- `core/data/` — bundled English/Vietnamese dictionaries.
- `core/tests/` — engine, simulation and parser-safety tests.
- `platform/macos/App/` — SwiftUI menu-bar application.
- `platform/macos/Input/` — macOS event-tap/input bridge.
- `platform/macos/tests/` — source-level input and security invariants.
- `tools/package.sh` — local/release packaging and notarization.
- `.github/workflows/` — CI and split-privilege release pipeline.

## Credits

This fork builds on:

- [`nghialuong/84Key`](https://github.com/nghialuong/84Key) — original 84Key macOS application.
- [`tuyenvm/OpenKey`](https://github.com/tuyenvm/OpenKey) — Vietnamese typing engine.
- [`google-10000-english`](https://github.com/first20hours/google-10000-english) — English word list used by automatic detection.

The upstream project's attribution is preserved in source files and [`NOTICE`](NOTICE).

## License

84Key is distributed under **GNU GPLv3** because the typing engine derives from
GPLv3-licensed OpenKey. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
