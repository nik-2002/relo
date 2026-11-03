# Relo Agent Notes

## Start Here

- `docs/agent-context/HANDOFF.md` — current state and open items. Read first.
- `docs/agent-context/environment.md` — how to build, test, and run this app here.
  Read before running any build, test, or launch command.
- `docs/agent-context/glasseffect-black-border.md` — why `.glassEffect` is not used.

## Build Quickstart

Xcode 27.2 at `/Applications/Xcode.app` is the active toolchain. No Apple signing
certificate is installed, so local builds are ad-hoc signed:

```sh
xcodebuild -project Relo.xcodeproj -scheme Relo -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Caches/relo-dd" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
```

## Repo Layout

- macOS app source lives in `Relo/` with the Xcode project at `Relo.xcodeproj`.
- Unit tests live in `ReloTests/`.
- `scripts/make-dmg.sh` packages a built app; `scripts/render-app-icon.swift` renders
  the 1024 px master icon (`Relo/AppIcon.png`) used to fill `AppIcon.appiconset`.

## Swift

- Swift 6 language mode. The app target defaults to `MainActor` isolation; mark pure
  value types `nonisolated` when they must be used off the main actor.
- The test target is `nonisolated` by default; test classes that touch app types are
  annotated `@MainActor` and use `async throws` `setUp`/`tearDown`.

## Docs

- In Markdown, wrap multi-line commands in fenced code blocks with blank lines around them so the MD linter passes.
- Leave a blank line before and after fenced code blocks.

## Release Workflow (Developer ID)

- The canonical release artifact is the signed + notarized DMG built locally (not the GitHub Actions build).
- Xcode: Archive → Distribute App → Direct Distribution to notarize the app.
- DMG packaging: use `scripts/make-dmg.sh` and set `SIGNING_IDENTITY` (required; script fails if missing).
- Notarize + staple the DMG with `notarytool`, then verify Gatekeeper on the installed app.

## macOS Menu Behavior

- Favor standard macOS behaviors and interaction patterns whenever possible. If a proposed change deviates from platform norms, call it out explicitly before implementing.

## Hard build storage rule

All building, compilation, packaging, testing, caching, and temporary-file activity must
happen on the **internal SSD**.

External volumes (`/Volumes/...`) are cold storage only. They may hold archives, installers,
source snapshots, and finished/verified app backups, but **no active build may depend on one
being mounted**.

Before starting any build:

1. Copy every required input to an internal path.
2. Set derived-data paths, temporary directories (`TMPDIR`), and output paths to internal
   locations.
3. Run `df -h /` and confirm there is enough free space.
4. Do not eject or disconnect a source drive while a build is reading it.

If internal space is insufficient, stop and free space with the user's approval. Never use
an external drive as a workaround.

**Reason:** external USB/APFS drives have detached during builds on this machine, causing
read failures and losing work. The internal SSD is required for reliability and speed.
