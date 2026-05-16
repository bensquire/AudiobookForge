# Releasing AudiobookForge

Cutting a signed, notarized DMG that Mac users can install without
Gatekeeper warnings. End-to-end: ~6 minutes in CI once the secrets are in
place.

## One-time setup

You need an **Apple Developer Program** membership ($99/yr). The "ad-hoc"
`codesign --sign -` path the debug build uses will *not* pass Gatekeeper —
distributing outside the App Store requires a Developer ID certificate
signed by Apple's CA, plus notarization through Apple's notary service.

### 1. Generate a Developer ID Application certificate

1. Open **Keychain Access** → Certificate Assistant → **Request a
   Certificate from a Certificate Authority…**. Save the request to disk.
2. Go to <https://developer.apple.com/account/resources/certificates/list>,
   click **+**, choose **Developer ID Application**, upload the request.
3. Download the resulting `.cer` and double-click to install in Keychain
   Access (in the **login** keychain). Verify with:
   ```
   security find-identity -v -p codesigning
   ```
   You should see a line containing `Developer ID Application: Your Name (TEAMID)`.

### 2. Export the certificate as `.p12`

1. In Keychain Access, expand the cert to reveal the private key.
2. Select **both** the cert and its private key, right-click → **Export 2
   items…**, choose `.p12`, set a strong password — call it `$P12_PWD` below.
3. Base64-encode it for the GitHub secret:
   ```
   base64 -i Certificates.p12 | pbcopy
   ```

### 3. Create an App Store Connect API key

The release workflow uses an API key (not a username/password) so it works
unattended.

1. Go to <https://appstoreconnect.apple.com/access/integrations/api>.
2. Click **+** under **Active**. Name it `AudiobookForge Notarization`.
   Access: **Developer**. Click **Generate**.
3. Download the `AuthKey_XXXXXXXXXX.p8` (you only get one shot at this).
4. Note the **Key ID** (the `XXXXXXXXXX` in the filename) and the
   **Issuer ID** (UUID shown at the top of the Keys page).
5. Base64-encode the key file:
   ```
   base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
   ```

### 4. Find your Apple Team ID

The 10-character alphanumeric ID at
<https://developer.apple.com/account/#MembershipDetailsCard>, also visible
in `security find-identity` output as `(XXXXXXXXXX)`.

### 5. Add GitHub repository secrets

In the repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
|---|---|
| `SIGNING_CERTIFICATE_P12_BASE64` | Output of step 2's `base64` |
| `SIGNING_CERTIFICATE_PASSWORD` | The `.p12` password from step 2 |
| `APPLE_TEAM_ID` | 10-char ID from step 4 |
| `APPLE_API_KEY_ID` | Step 3's Key ID |
| `APPLE_API_ISSUER_ID` | Step 3's Issuer ID |
| `APPLE_API_KEY_BASE64` | Output of step 3's `base64` |

GitHub redacts these from logs automatically; the workflow also wipes the
on-disk copies in a final cleanup step.

## Cutting a release

```sh
# bump the version in project.yml (MARKETING_VERSION), commit, then:
git tag v0.1.0
git push origin v0.1.0
```

The `release.yml` workflow fires on `v*` tags:

1. Imports the Developer ID cert into a throwaway keychain
2. `xcodebuild archive` with `MARKETING_VERSION=0.1.0` and
   `CURRENT_PROJECT_VERSION=<commit-count>`
3. `xcodebuild -exportArchive` with `developer-id` distribution
4. Submits the `.app` to Apple's notary service (`xcrun notarytool submit
   --wait`), staples the ticket
5. Packages a polished DMG via `create-dmg` (with the standard
   drag-to-Applications layout)
6. Signs the DMG, notarizes the DMG, staples
7. Creates a GitHub Release with auto-generated notes from `git log` and
   attaches the DMG

Watch progress in the **Actions** tab. Notarization is the slow step
(~3–5 min usually, occasionally >15). The workflow times out at 60.

### Manual re-run

If a release fails partway, you don't have to re-tag — go to **Actions →
Release → Run workflow**, optionally override the version.

## Cutting a release locally (dry-run)

Useful before pushing a tag, especially the first time. Same flow without
GitHub:

```sh
export APPLE_TEAM_ID=XXXXXXXXXX
export APPLE_API_KEY_ID=XXXXXXXXXX
export APPLE_API_ISSUER_ID=00000000-0000-0000-0000-000000000000
export APPLE_API_KEY_PATH=~/Downloads/AuthKey_XXXXXXXXXX.p8

brew install xcodegen create-dmg
scripts/release.sh 0.1.0
```

Output lands in `dist/AudiobookForge-0.1.0.dmg`. Open it; the install
window should be the polished one with the Applications shortcut. Drag
to Applications, launch from Spotlight — no Gatekeeper warning.

## Verifying a release after the fact

```sh
codesign --verify --deep --strict --verbose=2 /Applications/AudiobookForge.app
spctl --assess --type execute --verbose=4 /Applications/AudiobookForge.app
xcrun stapler validate /Applications/AudiobookForge.app
```

All three should pass cleanly.

## Versioning convention

- `MARKETING_VERSION` (what users see): SemVer, e.g. `0.1.0`, `1.2.3`.
  Edit in `project.yml` *or* override per-tag via the workflow input.
- `CURRENT_PROJECT_VERSION` (build number): commit count from
  `git rev-list --count HEAD`. Always monotonic, so future Sparkle-style
  auto-updates can compare it.

## Things that go wrong

| Symptom | Cause |
|---|---|
| `errSecInternalComponent` during signing | Keychain locked. CI handles this; locally, run `security unlock-keychain login.keychain`. |
| `Notarization status: Invalid` | Run `xcrun notarytool log <submission-id> ...` for the JSON report. Usually a missing hardened-runtime entitlement or an unsigned nested binary (check the bundled `ffmpeg`/`ffprobe` got signed — they do automatically via the embedded resource phase). |
| Gatekeeper still complains after install | Staple didn't run, or DMG wasn't notarized. Use the verification commands above. |
| "The application can't be opened" | Sometimes Finder caches the assessment. `xattr -dr com.apple.quarantine /Applications/AudiobookForge.app` clears it. |
| 403 on App Store Connect API | Key has expired (1 year max) or the role is too low. Recreate as **Developer**. |

## What's not here yet

- **Sparkle auto-updates** from GitHub Releases. Easy to bolt on — Sparkle
  reads an `appcast.xml` you'd publish to GitHub Pages alongside each
  release. The build-number we already emit makes upgrade comparisons
  straightforward.
- **Universal-binary verification step** that fails the build if the
  bundled `ffmpeg` isn't `arm64 + x86_64`.
- **Mac App Store path**. Requires an LGPL-only `ffmpeg` build (or
  swapping the encoder for AVFoundation) — see the licensing note in
  `README.md`.
