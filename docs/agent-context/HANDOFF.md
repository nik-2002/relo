# Relo — session handoff

Last active session: 2026-07-23/24. Written up 2026-08-12.

## Where things stand

The current working tree contains an uncommitted lifecycle simplification requested
on 2026-08-12. The first attempt kept Settings as a normal `NSWindow` but still called
`NSApp.activate`; the user verified that the gear button stuck pressed and Settings
did not appear. The current attempt removes application activation from the Settings
path entirely and uses a titled, floating, non-activating `NSPanel`. It is not marked
transient, so it should appear in Mission Control while `LSUIElement` keeps Relo out
of the Dock. The change builds cleanly and passed all 44 tests through Xcode's
`xctest` runner, but still needs a Finder-launched human verification.

The working tree also contains the user-approved compact menu-card controls. The card
is now 242 points wide. Its duration field remains empty and editable after a timer
starts so the user can prepare the next duration. The menu bar always reserves timer
width: while idle it shows the largest preset (25:00 by default) in an outlined pill;
while running it shows the countdown in a filled pill with cut-out numerals. Pausing
crossfades the current countdown to the same subdued outlined appearance as idle;
resuming crossfades it back to filled. All states use
compact medium-weight tabular numerals; the idle outline and numerals use subdued
30% template contrast while the running state uses full contrast. Starting and
cancelling use a pure 0.22-second AppKit crossfade with no scaling;
ordinary countdown ticks do not animate. The pill is 19 points tall so its vertical
padding divides evenly around the numerals. This prevents the menu card from jerking when
the timer starts. When idle the card shows `start`; while a timer runs the first
action in the same location is `pause`/`resume`, followed by `cancel` and `restart`.
The first action always reserves the width of `resume`, so pausing does not shift the
following controls or ellipsis.
Those two action groups now exchange with a 0.26-second native
SwiftUI snappy collapse/fade/scale transition. The gear icon is now an ellipsis that
opens Settings. Text actions use medium-weight type with no hover fill or outline;
only a brief opacity change acknowledges an actual press. Starting from the field or a preset keeps the card
open so the state transition is visible. Restart behavior has regression coverage.
With an empty duration field, clicking Start or pressing Return starts the same largest
preset displayed in the idle menu-bar pill. Explicitly typed input takes priority.
Settings preset fields reject non-numeric characters during editing and clamp manual
or stepper input to 1–1,440 minutes. A field may be temporarily empty so a one-digit
value can be replaced naturally; leaving it empty restores the last valid value.
Invalid or duplicate persisted values still resolve to the safe default preset set.

Alert volume is now a continuous native slider from 0–100% rather than four named
levels. Existing Very Low/Low/Medium/High preferences migrate to their former numeric
levels. Moving the slider adjusts an active tone preview immediately. The preview
button changes from Play to Stop during playback and changes back when playback ends.
The bundled Alarm Frenzy tone was removed and replaced by Bedside Clock and Digital
Tone MP3 resources.

## Private package status

A private Apple-silicon installer was produced on 2026-08-12 at
`dist/Relo-1.0-private.dmg`. It contains Relo 1.0 (build 1), is about 4.1 MB,
and has SHA-256
`5a80ff073e1e627594ce4ad429eee98b24cf4b69949d0d64464fc63fe6452aff`.
The clean build passed all 44 tests, the Release static analyzer, app code-integrity
verification, DMG checksum verification, and a single-process launch check of the
installed Release app.

No valid Developer ID or Apple Development signing identity is currently available in
the keychain. The private app and DMG are therefore ad-hoc signed and are not notarized.
Friends must use macOS's one-time manual Open approval; a normal Gatekeeper-trusted
distribution still requires a valid Developer ID Application certificate and Apple
notarization. The packaged app remains sandboxed and hardened.

The standard About panel now presents `Nico Estreba` as Relo's primary author and
then identifies the upstream project as `Tock by Michael Edelstone · MIT License`.
`LICENSE` adds Nico's 2026 copyright while preserving Michael Edelstone's original
2025–2026 copyright and the complete inherited MIT terms.

Relo is now alarm-only at timer completion. The notification setting, authorization
requests, banner delivery, notification actions, and UserNotifications framework
dependency were removed. The Release binary was checked for notification linkage and
UI strings, then copied to `/Applications/Relo.app` and launched as the sole Relo
process for user verification.

`main` is at `f7d24ec` and the working tree contains the uncommitted changes described
above. The top commit is an **unverified experiment** — it is the open item, see below.

Recent commits, newest first:

- `f7d24ec` wip: delay accessory demotion to dodge the activation throttle ← UNVERIFIED
- `54de074` fix: drop Liquid Glass on the menu popover, keep frosted material
- `4436493` fix: stop stopwatch pause/resume from losing fractions of a second
- `934f19f` fix: resolve Settings crash, unresponsive controls, and space-key input on macOS 27

`origin/main` is at `934f19f`, so the five commits above it are local-only. `main` is
the sole local branch; the old `liquid-glass-and-toggle-fix` was fully contained in
`main` and has been deleted.

## The verification target: Settings window repeatedly opens

**Symptom.** Clicking the gear button in the menu-bar popover does nothing — the button
darkens (the press registers) but no Settings window appears, and afterwards the other
popover buttons stop responding too. The minutes text field keeps working. It takes a
few open/close/start-a-timer cycles to trigger; the first Settings open always works.

**What is actually happening.** Every failure has the identical signature:

- `NSApp.setActivationPolicy(.regular)` succeeds.
- The window is really created, at the right size and position (verified with
  `CGWindowListCopyWindowInfo`).
- `NSApp.activate(ignoringOtherApps: true)` silently does nothing.

So the window exists offscreen-of-attention behind the frontmost app. This is not a
crash and not a hang — it is a failed activation.

**Working theory.** macOS has an undocumented focus-stealing throttle that starts
ignoring `activate(ignoringOtherApps:)` from an app that flips between `.accessory` and
`.regular` and calls `activate()` repeatedly in a short window. Relo is an `.accessory`
app that promotes to `.regular` on every Settings open and demotes
immediately on every close, so ordinary open/close/open/close usage churns the policy
exactly in that pattern.

**Commit `f7d24ec`** implemented that theory by delaying demotion. The current
uncommitted change supersedes that experiment: there is no promotion, demotion, or
`NSApp.activate` call in the Settings path. The key-window handoff goes directly from
the menu panel to a non-activating Settings panel.

**Status: builds cleanly, never tested.** The previous session ended right at the point
of asking the user to exercise it. It is a reasoned experiment, not a known fix — the
underlying OS heuristic is undocumented. Verify before trusting it, and be willing to
throw it away.

**Verification requires a human.** It cannot be reproduced headlessly (see
`environment.md` — activation behaves differently for CLI-launched instances, and the
repro needs genuine frontmost status via the window server). Ask the user to
double-click `Relo.app` in Finder, then aggressively cycle: open popover → Settings →
close → start a timer → reopen popover → Settings, several times over.

## Suggested next steps

1. Test the non-activating Settings-panel working tree with the user. Confirm repeated
   Settings opens, no Dock icon, and a Settings panel visible in Mission Control.
2. If it still fails, do not restore application activation or policy toggling. Remove
   the menu card's editable `TextField` as part of the planned Onigiri-style input
   redesign, then dismiss the menu card completely before presenting Settings.
3. Push `main` to `origin` — it is 5 commits ahead of `934f19f`, including two real
   fixes (`4436493`, `54de074`) that exist only on this machine.
4. The 44-test suite passed on 2026-08-12 by invoking Xcode's `xctest` runner against
   the built test bundle with the app executable directory in `DYLD_LIBRARY_PATH`.
   Continue using that path when `xcodebuild test` cannot launch the test host.

## Read next

- `environment.md` — how to build, run, and instrument this app here. Non-obvious; read
  before running anything.
- `settings-crash-macos27.md` — the earlier, *resolved* Settings crash, with dead ends.
- `glasseffect-black-border.md` — why `.glassEffect` is not used on the popover.
