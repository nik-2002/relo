# Releasing

This guide covers the end-to-end workflows for shipping Relo through supported distribution channels.

## Version, build, and tag rules

### App Store (App Store Connect)

- Version = what users see on the App Store.
- Build = Apple’s internal upload counter.
- Build must increase on every upload.
- After a version is live on the App Store, any update (even metadata-only) requires a new version number.
- You can reuse the same version only until it has been released to the App Store (for example, while in review or pending developer release).

### DMG (GitHub)

- Version must change for every public DMG.
- Build is optional and may stay at `1` if version always changes.

### GitHub tags

- One tag = one exact DMG
- Never replace a DMG under an existing tag.
- If you rebuild, make a new tag (new version, or same version with a build/suffix).

## Prerequisites

- Xcode installed.
- `Relo` scheme is shared in Xcode (Xcode → Manage Schemes → Shared).
- GitHub CLI (`gh`) for creating/editing release notes from the terminal.

## Development

Open `Relo.xcodeproj`, select the `Relo` scheme, and run from Xcode.

## Release paths

This repo supports two release paths: the Mac App Store flow and the signed + notarized DMG flow for GitHub releases.

### Mac App Store

Use this flow for the Mac App Store build (App Store Connect).

1. Bump the app version/build in Xcode.
   - Target `Relo` → General → Version (MARKETING_VERSION) and Build (CURRENT_PROJECT_VERSION).
   - Bump Build to a new integer _every upload_ (App Store Connect rejects reused build numbers).

2. Archive and upload from Xcode.
   - Product → Archive
   - Archive Organizer → Distribute App → App Store Connect → Distribute
   - Wait for the upload to finish. Xcode will show a confirmation screen when the build has been successfully delivered to App Store Connect.

3. Complete the release in App Store Connect.
   - App Store Connect → Apps → Relo.
   - If you haven’t created the version yet, click the “+” button and enter the new version number. Otherwise, just open the existing version record.
   - On the version page, in the Build section, click “Select a build” (or “+”) and choose the uploaded build.
   - Fill any required metadata (What’s New, etc.) and resolve validation errors.
   - Click “Save.”
   - Click “Add for Review.”
   - Draft submission window opens. Click “Submit for Review.”
   - After approval, the app will either go live automatically (if you chose automatic release) or you’ll click “Release This Version” to publish it manually.

### Signed & notarized DMG

Use this flow for the official non–App Store release. It produces a signed, notarized, and stapled DMG.

1. Bump the app version/build in Xcode.
   - Target `Relo` → General → Version (MARKETING_VERSION) and Build (CURRENT_PROJECT_VERSION).
   - These values control the app’s reported version everywhere (Finder, About screen, crash logs).

2. Archive and notarize the app in Xcode.
   - Target `Relo` → Signing & Capabilities:
     - Build configuration: Release (Archive uses Release by default)
     - Automatically manage signing: off
     - Provisioning profile: none
     - Team: your paid team
     - Signing Certificate: Developer ID Application
   - Product → Archive
   - Archive Organizer → Distribute App → Direct Distribution
   - Wait for notarization to succeed, then export `Relo.app`.

3. Verify the exported app passes Gatekeeper.

   ```bash
   spctl -a -vv /path/to/Relo.app
   ```

4. Build a DMG from the notarized app.

   ```bash
   cd /path/to/relo
   rm -rf dist
   mkdir -p dist
   SIGNING_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
     ./scripts/make-dmg.sh "/path/to/Relo.app" "dist/Relo.dmg"
   ```

5. Notarize the DMG with `notarytool`.
   - One-time setup (per machine, just run once):

     ```bash
     xcrun notarytool store-credentials "relo-notary"
     ```

   - Submit and wait (can take a few minutes):

     ```bash
     xcrun notarytool submit "dist/Relo.dmg" --keychain-profile "relo-notary" --wait
     ```

6. Staple and validate the DMG.

   ```bash
   xcrun stapler staple "dist/Relo.dmg"
   xcrun stapler validate "dist/Relo.dmg"
   ```

7. Final smoke check.
   - Mount `dist/Relo.dmg`, drag `Relo.app` to `/Applications`, then:

     ```bash
     spctl -a -vv /Applications/Relo.app
     ```

8. Launch `Relo.app` from `/Applications` and verify core timer, alarm, settings, and shortcut behavior.

#### Publish the release

1. Commit and push all release changes.
2. Create and push a lightweight tag with the next sequential version number.
   - `git tag vX.Y.Z`
   - `git push origin vX.Y.Z`
3. After tag is pushed, GitHub Actions creates a GitHub Release named after the tag.
4. Upload the signed DMG you produced locally (GitHub Actions does not upload artifacts).

   ```bash
   cd /path/to/relo
   gh release upload vX.Y.Z dist/Relo.dmg --clobber
   ```

   - If you see “release not found”, wait for GitHub Actions to finish and retry commands.
5. Add or update release notes.
   - `gh release edit vX.Y.Z --notes $'Highlights:\n- First item\n- Second item'`
6. Download and install the DMG from the GitHub Release. This DMG will match the signed + notarized artifact you uploaded.
