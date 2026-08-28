# Releasing SangKey (macOS)

Pushing a strict semantic-version tag such as `v0.4.0` triggers
[`.github/workflows/release.yml`](../.github/workflows/release.yml). The workflow
is intentionally fail-closed: source provenance is checked before Apple secrets
are exposed, the signed/notarized artifact is validated before handoff, and a
second human approval is required before the GitHub Release becomes public.

SangKey has no embedded updater. Users update by explicitly opening the live
GitHub Releases page in their browser.

## 1. GitHub protections required

Before the first public release, configure rulesets so:

- `main` is protected;
- PRs are required for `main`;
- direct/force pushes and deletion of `main` are blocked;
- `Core + security tests` and `Build macOS app + headless agent` are required;
- tags matching `v*` are protected against update/deletion.

Release preflight reads GitHub's protected-ref state. If either `main` or the
release tag is unprotected, signing does not start.

Configure the GitHub environment **`release`** with required reviewers. The
workflow deliberately uses that protected environment twice:

1. approval before the Developer ID/notarization job authorizes Apple secrets;
2. approval again before `Publish GitHub Release` lets a human test the exact
   notarized artifact on a real Mac.

Do not approve the second gate until the acceptance checklist below passes.

## 2. Required Apple credentials

Add these secrets to the protected `release` environment:

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_CERT_P12` | base64 Developer ID Application certificate + private key |
| `DEVELOPER_ID_CERT_PASSWORD` | password of the exported `.p12` |
| `DEVELOPER_ID_TEAM_ID` | expected Apple Team Identifier |
| `ASC_API_KEY_P8` | base64 App Store Connect API `.p8` key |
| `ASC_API_KEY_ID` | App Store Connect API Key ID |
| `ASC_API_ISSUER_ID` | App Store Connect API Issuer ID |

There is intentionally no updater/EdDSA private key.

Example certificate setup:

```sh
base64 -i devid.p12 -o devid.p12.b64
gh secret set DEVELOPER_ID_CERT_P12 --env release < devid.p12.b64
gh secret set DEVELOPER_ID_CERT_PASSWORD --env release
gh secret set DEVELOPER_ID_TEAM_ID --env release
```

Example notarization key setup:

```sh
base64 -i AuthKey_XXXXXX.p8 -o asc.p8.b64
gh secret set ASC_API_KEY_P8 --env release < asc.p8.b64
gh secret set ASC_API_KEY_ID --env release
gh secret set ASC_API_ISSUER_ID --env release
```

Delete local credential exports afterward.

## 3. What release CI verifies

### Secret-free preflight

- strict `vMAJOR.MINOR.PATCH` tag;
- tag checkout equals `GITHUB_SHA`;
- tag SHA equals current `main` HEAD;
- tag version equals `MARKETING_VERSION`;
- tag is protected;
- `main` is protected;
- complete engine/sanitizer/security suite passes.

### Build / sign / notarize

- exact **Xcode 26.6 build 17F113**;
- checksum-pinned XcodeGen 2.46.0;
- universal `arm64 + x86_64` launcher and `SangKeyAgent`;
- agent has no AppKit, ServiceManagement or Swift runtime linkage;
- release cannot fall back to Apple Development signing;
- nested agent identifier is `com.sangtrx.sangkey.agent`;
- both agent and app are signed by Developer ID Application;
- both `TeamIdentifier` values equal `DEVELOPER_ID_TEAM_ID`;
- nested agent is signed before the enclosing app;
- app and agent signatures verify;
- production English detector corpus files are present and match their reviewed
  byte-pinned Git blob SHAs in the built app and mounted DMG;
- DMG is notarized and stapled;
- DMG and mounted app pass Gatekeeper `spctl` assessment;
- DMG includes `LICENSE.txt`, `NOTICE.txt`, `THIRD_PARTY_DATA.txt`, and
  `SOURCE.txt` pointing at the exact corresponding-source commit;
- final `SHA256SUMS` is produced only after those checks.

### Publish

The notarized payload is uploaded as a short-lived Actions artifact. The publish
job has repository `contents: write` but does not reference Apple secrets. It uses
the same protected `release` environment so required reviewers get a **second
approval point after the artifact exists**.

Before approving that job, download the `notarized-release` artifact from the
workflow run and perform the acceptance test below.

## 4. Real-Mac signed-artifact acceptance

Test the exact notarized DMG produced by `build-sign-notarize`, preferably on a
Mac/user account without an existing SangKey registration:

1. Verify `SHA256SUMS` and `xcrun stapler validate`.
2. Mount the DMG and inspect `THIRD_PARTY_DATA.txt` plus `SOURCE.txt` before
   installation.
3. Install `SangKey.app` into `/Applications`.
4. Launch it once and enable the bundled background input agent.
5. If macOS reports approval required, approve it under **General → Login Items**.
6. Grant **Accessibility** to the actual `SangKeyAgent` identity.
7. Confirm Telex, VNI, English auto-detection, VI/EN hotkey, Spotlight and browser
   compatibility behavior in representative apps.
8. Close `SangKey.app`; typing must continue while the AppKit control process is
   gone.
9. Log out/in or reboot; the registered agent must return without reopening the
   control app.
10. Reopen the control app and confirm background-agent status reflects System
    Settings accurately.
11. Disable the agent, close/reopen the control app, and confirm it remains
    disabled. Re-enable and verify typing returns.
12. Replace the installed app with the same signed candidate again and confirm
    Accessibility/code identity remains stable.

If any step fails, **do not approve the publish job**. Fix on `main` and cut the
next version rather than publishing the failing artifact.

## 5. Cut a release

After post-merge `main` CI is green and repository/environment protections are in
place:

```sh
git switch main
git pull --ff-only
MAIN_SHA="$(git rev-parse HEAD)"
git tag v0.4.0 "$MAIN_SHA"
git push origin v0.4.0
```

Do not tag a side branch or an older main commit; preflight rejects it.

## 6. Verify the published payload

The live repository is currently:

<https://github.com/sangtrx/84Key/releases>

A later rename to `sangtrx/SangKey` is safe because GitHub preserves redirects
from the current repository URL.

After publication:

```sh
shasum -a 256 -c SHA256SUMS
xcrun stapler validate SangKey-v0.4.0.dmg
spctl -a -t open --context context:primary-signature SangKey-v0.4.0.dmg
```

After mounting:

```sh
APP="/Volumes/SangKey/SangKey.app"
AGENT="$APP/Contents/Resources/SangKeyAgent"

codesign --verify --deep --strict --verbose=2 "$APP"
codesign --verify --strict --verbose=2 "$AGENT"
codesign -d --verbose=4 "$APP"
codesign -d --verbose=4 "$AGENT"
spctl -a -vv --type execute "$APP"
lipo "$APP/Contents/MacOS/SangKey" -archs
lipo "$AGENT" -archs
otool -L "$AGENT"
cat /Volumes/SangKey/THIRD_PARTY_DATA.txt
cat /Volumes/SangKey/SOURCE.txt
```

Confirm the app ID, agent ID, expected Team ID, universal architectures, no heavy
agent linkage, English corpus provenance, notarization, Gatekeeper result and exact
source URL.

## 7. Local packaging

`tools/package.sh` regenerates the project, builds both products, signs nested code
in the correct order, copies GPL/provenance/source material, and creates the DMG.
A notarized build must pass `stapler` and Gatekeeper before the script succeeds.

A normal local package may use a development/ad-hoc identity. Public release sets
`SANGKEY_REQUIRE_DEVELOPER_ID=1` and `SANGKEY_EXPECTED_TEAM_ID`, so it cannot
silently fall back to Apple Development.

```sh
SANGKEY_ARCHS="arm64 x86_64" bash tools/package.sh
```

## 8. Updating users

The control menu item **Kiểm tra cập nhật…** currently opens:

<https://github.com/sangtrx/84Key/releases/latest>

The current URL intentionally resolves before the planned repository rename and
will redirect afterward.
