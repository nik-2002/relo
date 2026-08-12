# Relo — session handoff

Last active session: 2026-07-23/24. Written up 2026-08-12.

## Where things stand

`main` is at `f7d24ec` and the working tree is clean. The top commit is an **unverified
experiment** — it is the open item, see below.

Recent commits, newest first:

- `f7d24ec` wip: delay accessory demotion to dodge the activation throttle ← UNVERIFIED
- `54de074` fix: drop Liquid Glass on the menu popover, keep frosted material
- `4436493` fix: stop stopwatch pause/resume from losing fractions of a second
- `934f19f` fix: resolve Settings crash, unresponsive controls, and space-key input on macOS 27

Nothing since `0d3013d` has been pushed to `origin/main`. There is also a stale local
branch `liquid-glass-and-toggle-fix` whose work has since landed on `main`.

## The open bug: Settings window stops opening

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

**Commit `f7d24ec`** implements that theory: delay the demotion back to
`.accessory` by 3 seconds after Settings closes, and cancel the pending demotion if
Settings is reopened first (guarded by a `demotionGeneration` counter). Rapid cycles
then never toggle the policy at all.

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

1. Test `f7d24ec` with the user. Keep it if it holds, `git revert` it if not — it was
   committed only so this handoff is self-contained, not because it is trusted.
2. If it does not hold, the next thing worth trying is removing the policy toggle
   entirely — keep Relo `.regular` while Settings is open in a way that does not require
   repeated `activate()` calls, or find a way to show Settings without activation.
   Accept a persistent Dock icon if that is the cost.
3. Push `main` to `origin` — it is several commits ahead.

## Read next

- `environment.md` — how to build, run, and instrument this app here. Non-obvious; read
  before running anything.
- `settings-crash-macos27.md` — the earlier, *resolved* Settings crash, with dead ends.
- `glasseffect-black-border.md` — why `.glassEffect` is not used on the popover.
