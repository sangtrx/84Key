# Testing SangKey

SangKey is tested from pure engine logic through the packaged two-process macOS
runtime. Automated CI deliberately separates deterministic correctness/linkage
checks from the user-session permissions that must be validated on a real Mac.

```sh
bash core/tests/run_tests.sh
```

## 1. Engine harness — `core/tests/engine_test.cpp`

The harness drives the real C++ engine (`vKeyHandleEvent`) and reconstructs the
visible text with a reference decoder, asserting exact output. It covers Telex,
VNI, English detection, option boundaries and accumulated regression cases.

This validates the engine in isolation; it does not exercise macOS CGEvents,
Accessibility or background registration.

## 2. Typing simulation — `core/tests/typing_sim_test.cpp`

The simulation reproduces the important macOS output semantics around the engine:
literal pass-through, transformed replacement, restore behavior, backspaces and
word boundaries. It types continuously like a real user, catching integration
regressions the event-by-event engine harness alone cannot see.

No AppKit, CGEvent or Accessibility permission is needed, so this layer runs on
Linux CI as well as macOS.

### Article fixtures — `core/tests/cases/*.txt`

Additional text fixtures are auto-discovered. One expected-output case per line:

```text
<telex keys> => <expected output>
```

A TAB may be used instead of `=>`. Lines beginning with `#` are comments and
blank lines are ignored. Supported directives include input method, English
detection, orthography and spelling modes; see existing files in
`core/tests/cases/` for examples.

A line without an expected-output delimiter is treated as correct Vietnamese
text for the round-trip harness: it is converted to keystrokes, typed by the
simulation and compared with the original text.

Some article-style fixtures are intentionally report-oriented because proper
nouns, foreign technical words and spelling conventions can be outside the
bundled dictionaries. The built-in regression suites remain the strict CI gate.

## 3. Parser / sanitizer / security gates

`core/tests/run_tests.sh` also runs:

- ASan/UBSan coverage for malformed legacy macro/smart-switch parser data;
- send-layer/source invariants;
- SangKey distribution/security invariants in
  `platform/macos/tests/security_invariants_test.sh`.

The security gate checks, among other things, that the always-on process has no
network/clipboard/Keychain client, uses the explicit preferences contract,
contains no Swift runtime source, preserves the pinned engine provenance, bundles
the LaunchAgent rather than mutating user LaunchAgents, and keeps release
privileges separated.

## 4. macOS packaged-runtime CI

The macOS 26 job generates the Xcode project and builds the same `SangKey` scheme
that produces both products:

```text
SangKey.app                  ephemeral AppKit/ServiceManagement control
SangKeyAgent                 always-on headless input process
```

CI then audits the built artifacts rather than trusting source intent alone.
It requires:

- launcher links AppKit + ServiceManagement but no Swift runtime;
- agent links **no AppKit, ServiceManagement, SwiftUI, Combine or libswift**;
- bundled LaunchAgent plist points to `Contents/Resources/SangKeyAgent`;
- actual embedded agent starts in deterministic smoke mode and loads both real
  dictionaries;
- agent idle RSS stays below **30 MiB**;
- Release launcher and agent are both universal `arm64 + x86_64`;
- nested agent, enclosing app and DMG signatures verify;
- agent signing identifier reads back exactly as
  `com.sangtrx.sangkey.agent`;
- DMG passes `hdiutil verify`.

The smoke-only environment variable `SANGKEY_AGENT_CI_SMOKE=1` skips creation of
the Accessibility event tap so a hosted runner can measure the real agent heap
without a TCC prompt. It is a test hook, not an alternate production mode.

## 5. Live end-to-end on a real Mac

Hosted CI cannot approve Accessibility or Login Items. Before releasing a new
architecture or signing identity, validate the signed candidate on a real user
session.

### Background-agent lifecycle

1. Put the signed `SangKey.app` in `/Applications`.
2. Launch it and verify the control menu reports the expected background status.
3. Approve the background item in **System Settings → General → Login Items** if
   required.
4. Grant Accessibility to the SangKey input agent.
5. Close the control panel and verify `SangKeyAgent` remains running.
6. Type Vietnamese in several normal applications.
7. Reopen the control app, choose **Tắt bộ gõ nền**, and verify the helper stops.
8. Close/reopen the control app and verify it remains disabled rather than being
   silently re-registered.
9. Enable it again and verify input resumes.

Run only one event-based Vietnamese IME during this test.

### Text-field typing helper

When the signed agent is running and Accessibility is granted, the existing helper
can drive a real TextEdit field:

```sh
bash tools/e2e_type.sh "dd ddi tieesng vieejt"
```

The controlling terminal also needs Accessibility/Automation permission because
it is creating the test input.

### Spotlight / system search

System search fields can apply text asynchronously and are a critical live check:

```sh
bash tools/e2e_spotlight.sh
```

Verify rapid Vietnamese transformations do not leave doubled/stale characters.
The implementation detects supported Apple search fields and uses an Accessibility
atomic-replacement path with event-based fallbacks.

### Chromium address bar / web editor

Run the browser compatibility helper where available:

```sh
bash tools/e2e_url_bar.sh
```

Also manually type rapidly in a Chromium address bar and Google Docs/content-
editable field, because scheduling behavior in those surfaces cannot be perfectly
modeled by the pure simulation.

## 6. Code identity / Accessibility verification

A v0.4 release intentionally gives the headless helper its own stable signing
identifier. Inspect the packaged candidate:

```sh
APP="/Applications/SangKey.app"
AGENT="$APP/Contents/Resources/SangKeyAgent"

codesign --verify --strict --verbose=2 "$AGENT"
codesign -d --verbose=4 "$AGENT" 2>&1 | grep '^Identifier='
codesign --verify --deep --strict --verbose=2 "$APP"
```

The agent identifier must be:

```text
com.sangtrx.sangkey.agent
```

Use a real Apple Development or Developer ID signature for permission-persistence
checks. Ad-hoc binaries are useful for CI packaging smoke but do not prove the
same TCC lifecycle as the final signed artifact.

## Diagnostics

The inherited engine source still contains a historical `KEY84_TRACE` diagnostic
branch, but the hardened SangKeyAgent deliberately calls `unsetenv("KEY84_TRACE")`
before the input controller is initialized. Do **not** rely on setting that
environment variable in a shipping SangKey build; the security invariant is that
per-keystroke trace cannot be enabled at runtime.

For live-only defects, collect the exact app/agent version, macOS version, target
application, input mode and smallest reproducible keystroke sequence. Add a pure
engine/simulation regression whenever the failure can be modeled without TCC.
