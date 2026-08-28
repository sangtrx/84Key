# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-08-28

### Added

- Split-process macOS architecture: an ephemeral AppKit + ServiceManagement
  control app manages a headless `SangKeyAgent` that owns the event tap, typing
  engine and dictionaries.
- Bundled `SMAppService` LaunchAgent registration using
  `Contents/Library/LaunchAgents` + `BundleProgram`, without writing user/system
  LaunchAgent files or shelling out to `launchctl`.
- Shared explicit `com.sangtrx.sangkey` CFPreferences domain with Darwin
  notification propagation between control app and agent.
- Production footprint gate for the real embedded agent; current CI measurements
  keep idle RSS well below the 30 MiB budget while both dictionaries are loaded.
- Universal `arm64 + x86_64` launcher and agent verification.

### Changed

- Always-on runtime no longer links AppKit, ServiceManagement, Swift, SwiftUI or
  Combine. AppKit is resident only while the user opens the control surface.
- Accessibility retry now uses exponential backoff capped at 15 seconds instead
  of waking once per second indefinitely while approval is pending.
- Background-agent status is refreshed whenever the control menu opens or the app
  becomes active, so System Settings approval/revocation is reflected immediately.

### Security

- Release builds now require a Developer ID Application identity and verify the
  expected Apple Team Identifier for both the nested agent and enclosing app.
- Release preflight refuses unprotected `main` or unprotected release tags before
  Apple signing credentials are exposed.
- macOS CI/release toolchain is pinned to Xcode 26.6 build 17F113.
- Notarized release payloads must pass both `stapler` and Gatekeeper `spctl`
  assessment before publication.
- DMGs include `LICENSE.txt`, `NOTICE.txt`, and `SOURCE.txt` pointing to the exact
  corresponding source commit.

## [0.3.0] - 2026-08-28

### Changed

- Rebranded the hardened macOS distribution to **SangKey** with independent bundle
  identifiers under `com.sangtrx.sangkey`.
- Replaced the SwiftUI/Combine resident menu application with a zero-Swift native
  Objective-C++/AppKit control surface.
- Reduced global event-tap subscriptions to the events needed by the input path
  and added Mach-O linkage/footprint gates so heavy UI frameworks cannot silently
  return to the always-on runtime.

## [0.2.0] - 2026-08-28

### Added

- Hardened fork identity and a native macOS release pipeline for this repository.
- Secret-free release preflight that accepts only strict semantic-version tags on
  the exact current `main` commit, verifies the source version, and reruns the
  full core/security gate before Apple signing credentials become available.
- Universal `arm64 + x86_64` Release packaging and CI verification, so public
  builds support both Apple Silicon and Intel Macs on the documented macOS 14+
  baseline.
- Full engine and macOS typing-simulation ASan/UBSan runs in addition to the
  malformed-parser sanitizer suite.
- A Settings escape hatch for the paced browser/web-editor compatibility path.
- A dedicated alphanumeric-token regression gate, including sanitizer coverage,
  for developer-style input such as `dashboard1`, `sha256`, `utf8`, `h264` and
  `gpt5`, with VNI digit semantics checked separately.

### Fixed

- Accessibility status can no longer remain falsely red after the event tap has
  already started successfully; a live tap now counts as effective permission.
- The legacy typing-buffer `CHR()` accessor now bounds-checks relative probes such
  as `_index - 1`, preventing an empty-word `TypingWord[-1]` undefined-behavior
  read found by the expanded sanitizer gate.
- About now points to `sangtrx/84Key` as the hardened source while preserving the
  original `nghialuong/84Key` project and OpenKey attribution separately.
- Telex and Simple Telex now treat an unshifted digit as a token boundary, so an
  English/compound restore completes before the digit instead of leaving a
  temporary Vietnamese accent in alphanumeric code tokens. VNI is excluded from
  this policy because its numeric keys remain tone/vowel modifiers.
- Run at Login now reconciles its Settings toggle to the effective
  `SMAppService` state when registration is rejected or requires approval.
- Closing onboarding now releases its retained window/SwiftUI hosting tree rather
  than keeping a hidden first-run window alive for the menu-bar process lifetime.

### Security

- Removed the embedded auto-updater/appcast path from the hardened distribution;
  update checks are explicit browser navigation to this fork's Releases page.
- Release signing/notarization runs with repository read permission only, while
  publication is isolated in a separate job with no Apple credentials.
- Reusable GitHub Actions are immutable-SHA pinned. Checkout and artifact-handoff
  actions use reviewed Node 24 releases; XcodeGen is exact-version and SHA-256
  verified before execution.
- Signing material is destroyed before the artifact helper is invoked, and the
  publish job rechecks `SHA256SUMS` before creating the GitHub Release.
- The macOS signing job now uses BSD `/usr/bin/base64 -D` for secret decoding;
  CI executes that exact decoder syntax so a GNU-only flag cannot break the first
  real tagged release.

## [0.1.9] - 2026-08-19

### Fixed

- **A finished word losing its tone mark when you press space**: typing "sướng"
  and pressing space gave "sương "; "triển" gave "triên ". The word was correct the
  whole time it was being typed — only the break took the mark off. Telex accepts
  several key orders for the same syllable and the dictionary stores one of them,
  so a word typed as "suowngs" rather than the stored "suwowngs" was not recognised
  as Vietnamese; the check that undoes an accidental double-press of a tone key then
  counted the word's own initial consonant as that second press. Every syllable
  starting with s, r, x, f or j was exposed. The check now judges the word on screen,
  which has a single spelling, instead of the keys that produced it.

## [0.1.8] - 2026-08-19

### Fixed

- **Tone dropped when you type fast**: typing "sướng" (`suwowngs`) quickly gave
  "sương", and "triển" (`trieenr`) gave "triên" — the tone key left nothing
  behind at all, not even a literal `s`/`r`. The engine was right in every case;
  the burst it asks for (a run of backspaces, then the corrected letters) was
  being dropped on the way to the app. Backspaces were one cached event object
  posted again for each delete, and no synthetic event ever carried a timestamp,
  so a burst arrived as several identical events — the shape an app reads as key
  repeat and is free to collapse, which it only gets the chance to do when it is
  busy enough to take them in one pass. Each backspace is now its own event,
  every synthetic event is stamped and marked non-coalescing on the way out, the
  Accessibility retry that could stall the tap for up to a second is bounded to
  10 ms, and a tap the system disables now starts a new word instead of leaving
  the engine describing text that is no longer on screen.

## [0.1.7] - 2026-08-04

### Fixed

- **Words swallowed when you backspace into an earlier word**: going back past a
  space to fix a word you had already finished brought the word back on screen
  but not the keystrokes behind it, so the engine went on believing the few keys
  typed since were the raw form of the whole word. At the next word break the
  English restore acted on that: it deleted the word it could see and typed back
  what it held. Typing "animat", space, "ed", then backspacing into the previous
  word and finishing it left "ed" where "animated" should have been. The raw keys
  now travel with the word history, a backspace only keeps trusting them while
  they still describe what is on screen, and anything that rewrites a whole word
  from raw keys is declined outright when they cannot be vouched for.

## [0.1.6] - 2026-07-31

### Fixed

- **Slow English typing with Telex enabled**: compound words assembled from known
  English words, such as `dashboard`, `airdrop`, and `markdown`, are now restored
  correctly at the word boundary instead of losing letters or gaining Vietnamese
  tone marks. Valid Vietnamese Telex spellings remain protected across alternate
  tone and modifier-key orders.

## [0.1.5] - 2026-06-21

### Fixed

- **English typing — accent now clears immediately**: typing a word like `iss`
  showed the accented `ís` until you pressed space, because the doubled tone key
  (the escape that forces the literal English letters) only dropped the mark at the
  word break. The mark is now dropped the moment the word is detected as
  non-Vietnamese (`iss` → `is`, `ass` → `as`), so the stray accent never lingers
  mid-word. Full English words (`issue`, `assign`, `miss`) still type out whole,
  and the correction stays compatible with the browser/Google Docs empty-character
  fix.

## [0.1.4] - 2026-06-16

### Fixed

- **Google Docs (and browser fields) typing**: in browsers, a backspace fired
  back-to-back with the replacement was dropped by the async web layer — the
  insert landed before the deletion — so the doubled-tone restore "garr" → "gar"
  came out "gảar". Browser corrections now emit an empty character (U+202F) to
  reset the autocomplete/composition state, then paced backspaces before the
  insert. One mechanism now fixes both the address bar ("đủ" no longer "dđủ") and
  in-page editors like Google Docs.

## [0.1.3] - 2026-06-14

### Fixed

- **macOS 26 (Tahoe) Spotlight typing**: the Spotlight search field is now owned
  by the `com.apple.campo` process instead of `com.apple.Spotlight`, so the
  Accessibility atomic-replace path no longer matched and injected backspaces were
  dropped (e.g. "chúng" came out "chuúng"). Spotlight-like fields are now detected
  by bundle id **and** by AX behavior (an Apple search field exposing value +
  selected range), and fall back to a Shift+Left select-and-overwrite when the
  atomic replace can't run (N≠M, VNI, or AX failure).

## [0.1.0] - Unreleased

First macOS release.

### Added

- Vietnamese typing engine derived from OpenKey (GPLv3), with **Telex**, **VNI**,
  and **Simple Telex** input methods and the Unicode code table (TCVN3,
  VNI-Windows, Unicode Compound, and CP1258 also supported).
- **Automatic English detection**: while typing in Telex, English words are left
  undiacriticized without switching modes, favoring Vietnamese on ambiguous input.
- **Spotlight diacritic fix**: correct diacritic placement in Spotlight (and
  similar fields) even when typing quickly, via the Accessibility API, with a
  fallback to the normal path.
- Menu-bar SwiftUI app with a VI/EN indicator and quick toggle.
- Settings for input method, code table, feature toggles, run-on-startup, and a
  language-switch hotkey, persisted with registered defaults.
- First-run Accessibility onboarding and a warning about conflicts with other
  Vietnamese input methods.
- Vietnamese-by-Telex syllable dictionary generated from linguistic rules (no
  external word list); English word list from the public-domain
  google-10000-english set.
- **Privacy**: 100% local processing, no telemetry, no network calls for typing.
- C++ engine test harness, a keystroke-level simulation of the macOS output
  pipeline with drop-in `cases/*.txt` article fixtures, a live end-to-end script,
  and continuous integration.

[Unreleased]: https://github.com/sangtrx/84Key/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/sangtrx/84Key/releases/tag/v0.4.0
[0.3.0]: https://github.com/sangtrx/84Key/releases/tag/v0.3.0
[0.2.0]: https://github.com/sangtrx/84Key/releases/tag/v0.2.0
[0.1.0]: https://github.com/nghialuong/84Key/releases/tag/v0.1.0
