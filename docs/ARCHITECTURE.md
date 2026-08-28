# SangKey Architecture

SangKey separates the always-on typing runtime from the user interface. The goal
is to keep the process holding Accessibility/event-tap capability small while
preserving the proven OpenKey-derived C++ engine.

## Layout

```text
core/
  engine/       C++14 typing engine (OpenKey-derived, GPLv3)
  data/         english_words.dat, viet_telex.dat
  tests/        engine, simulation, parser/sanitizer and invariant gates

platform/macos/
  Agent/        SangKeyAgent.mm + bundled LaunchAgent plist
  App/          ephemeral AppKit/ServiceManagement control menu
  Input/        InputController.mm + EngineGlobals.cpp
  HeadlessCompat/
                narrow replacements for NSWorkspace,
                NSRunningApplication and NSEvent conveniences inherited by
                InputController when it is compiled into the headless agent
  Shared/       explicit CFPreferences domain + Darwin notification contract
  Resources/    Info.plist and app icon assets
  tests/        macOS distribution/security source invariants
  project.yml   XcodeGen spec -> SangKey.xcodeproj

tools/          dictionary generation, packaging and manual e2e helpers
```

## Process boundary

```text
SangKey.app                         SangKeyAgent
(ephemeral)                         (always-on)

AppKit                              Foundation
ServiceManagement                   ApplicationServices
menu/status UI                      Carbon
                                    Security
        │                           CGEventTap
        │ CFPreferences             C++ engine + dictionaries
        ├──────────────────────────►
        │ Darwin notification
        └──────────────────────────► reload options
```

`SangKey.app` does not contain `InputController` or the C++ typing engine. It
registers/unregisters the bundled LaunchAgent with `SMAppService`, edits shared
preferences and opens relevant System Settings pages. The control process may be
closed without stopping Vietnamese input.

`SangKeyAgent` owns the event tap, Accessibility compatibility paths, engine and
dictionaries. It deliberately does not link AppKit, ServiceManagement, Swift,
SwiftUI or Combine. CI audits the final Mach-O rather than relying only on source
layout.

## Background registration

The shipping application contains:

```text
SangKey.app/
  Contents/
    Resources/
      SangKeyAgent
      english_words.dat
      viet_telex.dat
    Library/
      LaunchAgents/
        com.sangtrx.sangkey.agent.plist
```

The plist uses `BundleProgram = Contents/Resources/SangKeyAgent` and is registered
through `SMAppService.agentServiceWithPlistName:`. SangKey does not install files
into `~/Library/LaunchAgents` and does not invoke `launchctl`.

The control app persists an `agentDesiredEnabled` preference so explicitly
disabling the background agent remains disabled when the control app is opened
again.

## Code identity

There are three intentional identities:

- release control app: `com.sangtrx.sangkey`
- debug control app: `com.sangtrx.sangkey.debug`
- input agent: `com.sangtrx.sangkey.agent`

`SangKeyAgent` is a command-line Mach-O, not an application bundle. Packaging
therefore passes its identifier explicitly to `codesign` and reads the identifier
back before signing the enclosing app. This gives the Accessibility-capable
helper a deterministic designated requirement across releases.

## Engine (`core/engine`)

The engine is pure C++14. Its main entry point is
`vKeyHandleEvent(event, state, keycode, capsStatus, otherControlKey)`. It keeps
the current word buffer and returns a `vKeyHookState` containing a decision code,
backspace count and replacement characters. Platform code converts that decision
into macOS events.

The legacy engine bytes retained in `EngineUpstream.inc` are treated as pinned
provenance and guarded by regression tests. SangKey-specific behavior is layered
around them rather than casually rewriting the mature typing core.

## macOS input core (`platform/macos/Input/InputController.mm`)

`InputController` installs a session-level `CGEventTap`. On key events it calls
the C++ engine and either lets the original event through or emits the required
backspaces/replacement characters. The same file also owns compatibility paths
for Spotlight/system search and browser/content-editable behavior.

The implementation came from an AppKit-based lineage. To avoid a high-risk
rewrite of this correctness-sensitive file, the headless target puts
`HeadlessCompat` first in its header search path. Only three inherited AppKit
conveniences are substituted:

- frontmost application lookup;
- process signing/bundle identifier lookup;
- `charactersIgnoringModifiers` keyboard-layout translation.

The adapter uses Carbon/TIS and Security APIs and caches the current frontmost
process/signing identifier so expensive signing lookup is not repeated on every
keystroke. The event/engine transformation code remains shared with the proven
implementation.

## English auto-detection

Two dictionaries are keyed by raw Telex keystrokes: a common-English list and a
Vietnamese-by-Telex syllable list. They are loaded by `SangKeyAgent` from the
application Resources directory. The engine consults them around transformation
boundaries to suppress unwanted Vietnamese marks in English words while retaining
valid Vietnamese spellings.

Measurements showed that both dictionaries add only a small fraction of the old
AppKit process's idle RSS, so v0.4 keeps the existing representation instead of
rewriting a correctness-sensitive lookup path for a minor memory gain.

## Spotlight fix

Some system search fields can apply injected events asynchronously and lose a
backspace. For supported targets, `InputController` uses Accessibility to inspect
the focused search field and can replace the affected text atomically. Failure
falls back to the normal/select-and-overwrite event path rather than changing
behavior globally.

## Options and persistence

The explicit preference domain is `com.sangtrx.sangkey`.
`SangKeyPreferences.*` reads/writes values with `CFPreferences`, and changes are
announced with the Darwin notification
`com.sangtrx.sangkey.preferences-changed`. The agent reloads its engine globals
from that domain; the control app reads the same domain for menu state.

A VI/EN hotkey change originating inside the agent is also written back to the
shared preferences so the next control-panel launch reflects the actual mode.
There is no XPC service or database between the two processes.
