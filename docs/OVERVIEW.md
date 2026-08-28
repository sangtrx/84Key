# SangKey — Product & Feature Overview

> Plain-language reference for what SangKey is and how the current macOS product behaves.
> For internals see [`ARCHITECTURE.md`](ARCHITECTURE.md); for build/test details see
> [`BUILD.md`](BUILD.md) and [`TESTING.md`](TESTING.md).

## What it is

SangKey is a free, open-source **Vietnamese input method for macOS**. It types
Vietnamese with Telex, VNI and Simple Telex across normal macOS applications
while keeping the always-running input process unusually small.

The typing engine descends from the GPLv3 OpenKey/84Key lineage. SangKey keeps
that mature C++ core and focuses its macOS-specific work on compatibility,
privacy, security and runtime footprint.

- **Platform:** macOS 14+.
- **License:** GNU GPLv3.
- **Release control-app bundle id:** `com.sangtrx.sangkey`.
- **Input-agent code identifier:** `com.sangtrx.sangkey.agent`.
- **Privacy:** typing conversion is local; the input agent has no telemetry,
  account, cloud-sync or background-network path.
- **Distribution:** universal `arm64 + x86_64`, Developer ID signed and Apple
  notarized when built by the release workflow.

## How it works

The product contains two processes with different jobs.

**`SangKeyAgent`** is the background input process. It owns the session-level
`CGEventTap`, C++ engine, dictionaries and the Accessibility-based compatibility
paths. It does not link AppKit, ServiceManagement or Swift runtime machinery.

**`SangKey.app`** is a small control surface. Open it when you want to change the
input mode/options, enable or disable the background agent, open System Settings,
or check for a new release. Closing this control app does **not** stop typing.

Settings are shared through an explicit local CFPreferences domain and a Darwin
notification. No XPC service or database is required.

## Main features

1. **Accurate Vietnamese typing** — Telex, VNI and Simple Telex backed by the
   OpenKey-derived C++ engine.
2. **Automatic English detection** — common English words can pass through Telex
   without accidental Vietnamese transforms. English and Vietnamese-by-Telex
   dictionaries are loaded locally by the background agent.
3. **Spotlight/system-search compatibility** — for search fields that can lose
   injected backspaces, SangKey can use the Accessibility API to perform a local
   atomic text replacement, with safe fallbacks.
4. **Browser / Google Docs compatibility** — the event sender includes targeted
   handling for asynchronous browser/content-editable behavior rather than
   slowing every application globally.
5. **Very small always-on runtime** — AppKit and ServiceManagement live only in
   the control process. CI measures the actual headless agent with production
   dictionaries loaded and enforces a 30 MiB idle-RSS ceiling.
6. **Independent control and typing lifecycle** — the user can close the control
   panel while the registered LaunchAgent keeps running, or explicitly disable
   the background input agent and have that choice persist.

## User controls

The current control menu exposes the deliberately small set of options supported
by the v0.4 product surface:

### Language and input

- **Vietnamese / English** mode.
- **Input method:** Telex (default), VNI, Simple Telex 1, Simple Telex 2.
- Default VI/EN switch hotkey: **⌃⌘Space**.

### Smart typing

- **Automatic English detection** — default ON.
- **Vietnamese spelling check** — default ON.
- **Modern orthography** — default ON.

### Compatibility

- **Spotlight/system search fix** — default ON.
- **Browser / Google Docs fix** — default ON.

### System

- See whether the background agent is enabled, disabled or awaiting macOS approval.
- Enable or disable the background agent.
- Open **Privacy & Security → Accessibility**.
- Open **General → Login Items** for background-item approval.
- Open the SangKey GitHub Releases page to check for updates.
- Close the control panel while leaving the input agent running.

The underlying engine still contains additional compatibility/options inherited
from its lineage, but SangKey does not advertise a control as user-facing unless
the current control app actually exposes it.

## Permissions and setup

1. Copy `SangKey.app` to `/Applications`.
2. Launch it once. The app registers its bundled user-session LaunchAgent through
   Apple's `SMAppService` API when background typing is desired.
3. If macOS marks the background item as requiring approval, open **Login Items**
   from SangKey and approve it.
4. Grant **Accessibility** to the SangKey input agent under **Privacy & Security →
   Accessibility**. The agent needs this powerful permission to observe and post
   keyboard events system-wide.
5. Disable other event-based Vietnamese IMEs to avoid multiple event taps
   transforming the same keystrokes.
6. Close the SangKey control panel if you do not need it; input continues in the
   background agent.

For secure/password input, SangKey relies on macOS **Secure Event Input** as the
platform boundary. It does not claim a custom password-field detector.

## Background lifecycle

The helper is shipped inside the application bundle together with its LaunchAgent
plist. SangKey does not write into the user's `~/Library/LaunchAgents` directory
and does not invoke `launchctl` itself.

Choosing **Tắt bộ gõ nền** records an explicit disabled preference and unregisters
the service. Reopening the control app respects that choice instead of silently
turning the helper back on.

## Updates

There is no background update checker or embedded installer. **Kiểm tra cập nhật…**
opens the public SangKey GitHub Releases page in the default browser. Release
payloads are expected to include a notarized DMG and `SHA256SUMS`.

## What SangKey does not do

- No telemetry or analytics.
- No account or cloud sync.
- No background HTTP client in the input agent.
- No clipboard or Keychain client in the input agent.
- No XPC service or database between launcher and agent.
- No Swift/SwiftUI/Combine in the v0.4 macOS runtime.
- No persistent AppKit settings/window graph inside the Accessibility-enabled
  always-on process.
- No manual `launchctl` installation flow.

## Credits

SangKey is independently branded while preserving upstream attribution to:

- [`nghialuong/84Key`](https://github.com/nghialuong/84Key)
- [`tuyenvm/OpenKey`](https://github.com/tuyenvm/OpenKey)
- [`google-10000-english`](https://github.com/first20hours/google-10000-english)

See [`NOTICE`](../NOTICE) and the source headers for lineage details.
