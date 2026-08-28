# Releasing SangKey (macOS)

Pushing a strict semantic-version tag such as `v0.4.0` triggers
[`.github/workflows/release.yml`](../.github/workflows/release.yml). Before Apple
credentials are made available, a secret-free preflight verifies that the tag is
the exact current `main` commit, the tag matches `MARKETING_VERSION`, the full
core/security gate passes, **main is protected**, and the release tag itself is a
**protected ref**.

Only then does the workflow build universal `arm64 + x86_64` versions of both the
control launcher and the embedded headless `SangKeyAgent`, sign with the expected
Developer ID team, notarize the DMG with Apple, run Gatekeeper assessment, compute
SHA-256, and hand the payload to a separate publish job.

SangKey deliberately has **no in-app auto-updater or appcast**. Users update by
opening the live GitHub Releases page from the control menu and installing a
signed/notarized DMG themselves.

## 1. Repository protections required before the first release

The release workflow is intentionally fail-closed. Configure GitHub rulesets so:

- `main` is protected;
- direct/force pushes and deletion of `main` are blocked;
- PRs are required for `main`;
- the `Core + security tests` and `Build macOS app + headless agent` checks are
  required before merge;
- tags matching `v*` are protected against update/deletion.

The release preflight reads GitHub's protected-ref state. If either `main` or the
release tag is unprotected, signing does not start.

The protected `release` environment should also require manual approval for public
release signing.

## 2. Required Apple credentials

Create a protected GitHub environment named `release` and add:

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_CERT_P12` | base64 Developer ID Application certificate + private key |
| `DEVELOPER_ID_CERT_PASSWORD` | password of the exported `.p12` |
| `DEVELOPER_ID_TEAM_ID` | expected Apple Team Identifier; verified from signed agent + app |
| `ASC_API_KEY_P8` | base64 App Store Connect API `.p8` key |
| `ASC_API_KEY_ID` | App Store Connect API Key ID |
| `ASC_API_ISSUER_ID` | App Store Connect API Issuer ID |

There is intentionally **no updater/EdDSA private key**.

### Export the Developer ID certificate

Export the Developer ID Application certificate and private key from Keychain
Access as `devid.p12`, then:

```sh
base64 -i devid.p12 -o devid.p12.b64
gh secret set DEVELOPER_ID_CERT_P12 --env release < devid.p12.b64
gh secret set DEVELOPER_ID_CERT_PASSWORD --env release
gh secret set DEVELOPER_ID_TEAM_ID --env release
```

### Create the notarization API key

Create an App Store Connect API key with the minimum role required for
notarization, download its `.p8` file once, then:

```sh
base64 -i AuthKey_XXXXXX.p8 -o asc.p8.b64
gh secret set ASC_API_KEY_P8 --env release < asc.p8.b64
gh secret set ASC_API_KEY_ID --env release
gh secret set ASC_API_ISSUER_ID --env release
```

Delete local credential exports after loading the secrets:

```sh
rm -f devid.p12 devid.p12.b64 AuthKey_XXXXXX.p8 asc.p8.b64
```

## 3. Release security model

### Secret-free preflight

- runs on Ubuntu with `contents: read` only;
- accepts only tags matching `vMAJOR.MINOR.PATCH`;
- verifies the tag checkout is exactly `GITHUB_SHA`;
- fetches `origin/main` and requires the tag SHA to equal the **current main HEAD**;
- requires the tag version to match `MARKETING_VERSION`;
- requires GitHub to report the tag as protected;
- requires GitHub to report `main` as protected;
- runs `core/tests/run_tests.sh`, including engine/typing tests, sanitizer runs,
  parser safety and split-runtime security invariants;
- has no access to the protected `release` environment or Apple credentials.

### Build / sign / notarize

- starts only after preflight succeeds;
- uses the protected `release` environment;
- repository permission is **`contents: read` only**;
- runs on macOS 26 with **Xcode 26.6 build 17F113 pinned exactly**;
- reusable Actions are immutable-SHA pinned;
- XcodeGen 2.46.0 is downloaded from its exact GitHub release and verified against
  SHA-256 `4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`;
- builds the launcher and `SangKeyAgent` as universal `arm64 + x86_64` binaries;
- verifies `SangKeyAgent` does not link AppKit, ServiceManagement, SwiftUI,
  Combine or the Swift runtime;
- refuses to fall back to Apple Development for a release build;
- signs the nested agent first using code identifier
  **`com.sangtrx.sangkey.agent`** and Hardened Runtime;
- verifies both nested agent and app are signed by **Developer ID Application**
  and that both `TeamIdentifier` values equal `DEVELOPER_ID_TEAM_ID`;
- signs and deep-verifies the enclosing `SangKey.app` only after the nested code
  has its final signature;
- verifies the bundled LaunchAgent descriptor points at
  `Contents/Resources/SangKeyAgent`;
- signs and notarizes the final DMG;
- validates the notarization ticket with `stapler`;
- runs Gatekeeper `spctl` against both the DMG and the mounted application;
- asserts no Sparkle framework or source-only `EngineUpstream.inc` is shipped;
- verifies the DMG contains `LICENSE.txt`, `NOTICE.txt`, and `SOURCE.txt` pointing
  at the exact source commit;
- creates final `SHA256SUMS` only after notarization/stapling/Gatekeeper checks.

### Publish

- receives only the validated DMG and checksum through a short-lived Actions artifact;
- has **no Apple signing/notarization secrets**;
- receives `contents: write` only for creating the GitHub Release;
- verifies `SHA256SUMS` again before publishing;
- uses GitHub's `gh` CLI instead of a third-party release action.

## 4. Cut a release

Update `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` when appropriate, merge to
`main`, and wait for the **post-merge main CI run** to pass. Then create the tag
through a protected-tag path that does not permit later movement/deletion.

```sh
git switch main
git pull --ff-only
MAIN_SHA="$(git rev-parse HEAD)"
git tag v0.4.0 "$MAIN_SHA"
git push origin v0.4.0
```

Do not tag a side branch or an older main commit. Release preflight rejects it.

## 5. Verify the published payload

The live repository is currently:

<https://github.com/sangtrx/84Key/releases>

The planned repository rename to `sangtrx/SangKey` can happen later; GitHub keeps
redirects from the old repository URL after rename.

Download both the DMG and `SHA256SUMS`, then:

```sh
shasum -a 256 -c SHA256SUMS
xcrun stapler validate SangKey-v0.4.0.dmg
spctl -a -t open --context context:primary-signature SangKey-v0.4.0.dmg
```

After mounting the DMG, verify both launcher and input agent:

```sh
APP="/Volumes/SangKey/SangKey.app"
AGENT="$APP/Contents/Resources/SangKeyAgent"

codesign --verify --deep --strict --verbose=2 "$APP"
codesign --verify --strict --verbose=2 "$AGENT"
codesign -d --verbose=4 "$AGENT"
codesign -d --verbose=4 "$APP"
spctl -a -vv --type execute "$APP"
lipo "$APP/Contents/MacOS/SangKey" -archs
lipo "$AGENT" -archs
otool -L "$AGENT"
cat /Volumes/SangKey/SOURCE.txt
```

Confirm:

- app bundle identifier is `com.sangtrx.sangkey`;
- agent signing identifier is `com.sangtrx.sangkey.agent`;
- both signed Team Identifiers match the expected release team;
- both launcher and agent contain `arm64` and `x86_64`;
- the agent has no AppKit / ServiceManagement / Swift runtime linkage;
- Developer ID belongs to the SangKey release owner;
- Apple notarization and Gatekeeper assessment validate;
- `SOURCE.txt` points at the exact release source commit.

## 6. Local packaging

`tools/package.sh` regenerates the Xcode project from `project.yml`, builds both
products, embeds the LaunchAgent descriptor, signs nested code in the correct
order, copies GPL/provenance/source material, then creates the DMG.

A normal local package can use a local development/ad-hoc identity. A release build
sets `SANGKEY_REQUIRE_DEVELOPER_ID=1` and `SANGKEY_EXPECTED_TEAM_ID` so it cannot
fall back to an Apple Development signer.

To reproduce the universal release architecture locally:

```sh
SANGKEY_ARCHS="arm64 x86_64" bash tools/package.sh
```

## 7. Updating users

There is no background update check. The control menu item **Kiểm tra cập nhật…**
currently opens:

<https://github.com/sangtrx/84Key/releases/latest>

The browser/download flow is outside the always-on input agent. The old repository
URL is intentionally used until the GitHub rename is actually completed, because
it resolves today and GitHub redirects it after rename.
