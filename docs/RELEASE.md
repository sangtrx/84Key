# Releasing the hardened 84Key fork (macOS)

Pushing a version tag (for example `v0.2.0`) triggers
[`.github/workflows/release.yml`](../.github/workflows/release.yml). The workflow
builds the app, signs it with Developer ID, notarizes the DMG with Apple, computes
a SHA-256 checksum, then hands the result to a separate job that publishes the
GitHub Release.

This fork deliberately has **no in-app auto-updater or appcast**. Users update by
opening the GitHub Releases page from the menu and installing a signed/notarized
DMG themselves. This removes the updater framework, installer helpers, updater
signing key, and background network path from the Accessibility-enabled process.

## 1. Required Apple credentials

Create a protected GitHub environment named `release` and add:

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_CERT_P12` | base64 Developer ID Application certificate + private key |
| `DEVELOPER_ID_CERT_PASSWORD` | password of the exported `.p12` |
| `ASC_API_KEY_P8` | base64 App Store Connect API `.p8` key |
| `ASC_API_KEY_ID` | App Store Connect API Key ID |
| `ASC_API_ISSUER_ID` | App Store Connect API Issuer ID |

There is intentionally **no updater/EdDSA private key** in this fork.

### Export the Developer ID certificate

Export the Developer ID Application certificate and private key from Keychain
Access as `devid.p12`, then:

```sh
base64 -i devid.p12 -o devid.p12.b64
gh secret set DEVELOPER_ID_CERT_P12 --env release < devid.p12.b64
gh secret set DEVELOPER_ID_CERT_PASSWORD --env release
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

## 2. Release security model

The workflow has two jobs with deliberately different authority.

### Build / sign / notarize

- protected `release` environment;
- Apple credentials are available here;
- GitHub repository permission is **`contents: read` only**;
- `actions/checkout` is pinned to an immutable commit SHA;
- XcodeGen 2.46.0 is downloaded from its exact GitHub release URL and checked
  against SHA-256
  `4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`
  before execution;
- the final DMG is Developer ID signed and Apple notarized;
- the workflow asserts that no `Sparkle.framework` is embedded;
- a final `SHA256SUMS` file is generated after notarization/stapling.

### Publish

- receives only the notarized DMG and checksum through a short-lived GitHub
  Actions artifact;
- has **no Apple signing/notarization secrets**;
- receives `contents: write` only for creating the GitHub Release;
- verifies `SHA256SUMS` again before publishing;
- uses the GitHub-hosted `gh` CLI instead of a third-party release action.

This separation means a publish-step compromise does not receive the Developer
ID certificate or App Store Connect key, while code running with those Apple
credentials cannot modify repository contents or publish a release.

## 3. Cut a release

Update `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in
`platform/macos/project.yml` when appropriate, merge the change to `main`, then
tag the exact commit you intend to ship:

```sh
git switch main
git pull --ff-only
git tag v0.2.0 <EXACT_COMMIT_SHA>
git push origin v0.2.0
```

The release workflow verifies that the checked-out commit is exactly
`GITHUB_SHA` for the tag before importing signing credentials.

## 4. Verify the published payload

Download both the DMG and `SHA256SUMS` from the GitHub Release:

```sh
shasum -a 256 -c SHA256SUMS
xcrun stapler validate 84Key-v0.2.0.dmg
spctl -a -t open --context context:primary-signature 84Key-v0.2.0.dmg
```

After mounting the DMG, you can additionally verify the application:

```sh
codesign --verify --deep --strict --verbose=2 /Volumes/84Key/84Key.app
codesign -dv --verbose=4 /Volumes/84Key/84Key.app
```

Confirm the bundle identifier is `com.sangtrx.key84` and the signing identity is
the one controlled by this fork's release owner.

## 5. Local packaging

`tools/package.sh` always regenerates the Xcode project from `project.yml` before
building. Install XcodeGen yourself for local development and verify the source
or package you use. CI does **not** use Homebrew for XcodeGen; it uses the
checksum-pinned release archive described above.

For a local notarized build, configure either a notarytool keychain profile or
the `KEY84_ASC_KEY_PATH`, `KEY84_ASC_KEY_ID`, and `KEY84_ASC_ISSUER_ID`
environment variables documented in `tools/package.sh`.

## 6. Updating users

There is no background update check. The menu item **Kiểm tra cập nhật…** opens:

<https://github.com/sangtrx/84Key/releases/latest>

The browser/download flow is intentionally outside the keyboard process. Users
should install only a release whose checksum, Developer ID signature, and Apple
notarization validate successfully.
