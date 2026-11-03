# Relo — session handoff

Last updated 2026-11-03.

## Where things stand

Relo 1.1 (build 3) is the current version. The 2026-11-03 housekeeping pass:

- Moved the project to Xcode 27.2 recommended settings, Swift 6 language mode, and
  `MainActor` default isolation for the app target. The build is warning-free.
- Updated `KeyboardShortcuts` from 1.17.0 to 3.1.0.
- Removed the inherited Tock marketing site (it was never published from this repo and
  carried a third-party analytics tag), unused icon drafts, the unused `.icns` /
  `.iconset`, unreferenced image sets and sound files, and the empty Preview Content
  catalog.
- All 56 unit tests pass through Xcode's `xctest` runner (see `environment.md`).

The Release build is ad-hoc signed, sandboxed, and hardened. It is not notarized: no
Developer ID or Apple Development identity is in the keychain. Friends installing the
private DMG need macOS's one-time manual Open approval.

The About panel credits `Nico Estreba` as primary author and the upstream project as
`Tock by Michael Edelstone · MIT License`. Relo is alarm-only at timer completion; the
notification feature and UserNotifications dependency were removed in August.

## Open items

1. **Settings panel verification.** On 2026-08-12 Settings was changed to a titled,
   floating, non-activating `NSPanel` with no `NSApp.activate` call, to work around a
   macOS activation throttle that made the gear button stick after a few
   open/close cycles. There is no later record of a Finder-launched verification.
   If Settings fails to appear again, do not reintroduce activation-policy toggling;
   see the August notes in git history (`git log -- docs/agent-context/HANDOFF.md`).
2. **Signed distribution.** A Gatekeeper-trusted DMG still needs a Developer ID
   Application certificate and notarization (see `RELEASING.md`).
3. **Windows port.** The `windows-port` branch holds a C# port of the timer parser and
   its own handoff brief; it is not merged.

## Read next

- `environment.md` — how to build, test, and run this app here.
- `glasseffect-black-border.md` — why `.glassEffect` is not used on the popover.
