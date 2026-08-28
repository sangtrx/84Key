# Releasing SangKey (macOS)

Pushing a strict semantic-version tag such as `v0.4.0` triggers
[`.github/workflows/release.yml`](../.github/workflows/release.yml). The workflow
is intentionally fail-closed around source provenance and the Apple distribution
chain, but GitHub branch/tag rulesets are optional for this personal repository.

SangKey has no embedded updater. Users update by explicitly opening the live
GitHub Releases page in their browser.

## 1. Release source requirements

Before creating a tag:

- post-merge `main` CI must be green;
- the release tag must point to the **exact current `main` HEAD**;
- the tag must be strict `vMAJOR.MINOR.PATCH`;
- that version must equal `MARKETING_VERSION` in `platform/macos/project.yml`.

Branch/tag protection is recommended for shared repositories, but SangKey's
release workflow does **not** require a GitHub ruleset. Exact-main provenance is
still mandatory and is checked again by release preflight before Apple secrets
are exposed.

Configure the GitHub environment **`release`** if you want approval gates or
store Apple credentials there. The workflow uses that environment twice:

1. before the Developer ID/notarization job;
2. before `Publish GitHub Release`, so the exact notarized artifact can be tested
   on a real Mac before publication.

If the environment has no required reviewers, those jobs proceed without a
manual approval pause.

## 2. Required Apple credentials

Provide these secrets to the `release` environment or otherwise make them
available to the workflow:

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
- app and agent signatures verify;
- production English detector corpus files match their reviewed byte-pinned Git
  blob SHAs in the built app and mounted DMG;
- DMG is notarized and stapled;
- DMG and mounted app pass Gatekeeper `spctl` assessment;
- DMG includes `LICENSE.txt`, `NOTICE.txt`, `THIRD_PARTY_DATA.txt`, and
  `SOURCE.txt` pointing at the exact corresponding-source commit;
- final `SHA256SUMS` is generated and verified before publication.

### Publish

The notarized payload is uploaded as a short-lived Actions artifact. The publish
job has `contents: write` but does not receive Apple signing material.

## 4. Real-Mac signed-artifact acceptance

Before making a public release, test the exact notarized DMG produced by
`build-sign-notarize`, preferably on a Mac/user account without an existing
SangKey registration:

1. Verify `SHA256SUMS` and `xcrun stapler validate`.
2. Install `SangKey.app` into `/Applications`.
3. Launch it once and enable the bundled background input agent.
4. Approve it under **General → Login Items** if macOS asks.
5. Grant **Accessibility** to the actual `SangKeyAgent` identity.
6. Confirm Telex, VNI, English auto-detection, VI/EN hotkey, Spotlight and browser compatibility.
7. Close `SangKey.app`; typing must continue.
8. Log out/in or reboot; the agent must return without reopening the control app.
9. Disable/re-enable the agent and verify state persists correctly.
10. Reinstall the same signed candidate and confirm Accessibility/code identity remains stable.

If any step fails, do not publish that artifact.

## 5. Cut v0.4.0

After `main` CI is green:

```sh
git switch main
git pull --ff-only
MAIN_SHA="$(git rev-parse HEAD)"
git tag v0.4.0 "$MAIN_SHA"
git push origin v0.4.0
```

Do not tag a side branch or an older `main` commit; preflight rejects it.

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

## 7. Local packaging

`tools/package.sh` regenerates the project, builds both products, signs nested
code in the correct order, copies GPL/provenance/source material, and creates the
DMG. A notarized build must pass stapler and Gatekeeper before the script succeeds.

```sh
SANGKEY_ARCHS="arm64 x86_64" bash tools/package.sh
```

## 8. Updating users

The control menu item **Kiểm tra cập nhật…** currently opens:

<https://github.com/sangtrx/84Key/releases/latest>

The current URL intentionally resolves before the planned repository rename and
will redirect afterward.
