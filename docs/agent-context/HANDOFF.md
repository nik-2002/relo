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

## Reminders focus (1.2, build 4)

A timer can be committed to an open Apple Reminders task. The menu card has one
"for a reminder…" line (`ReminderFocusRow`) that opens a native menu of incomplete
reminders grouped by list. The linked task shows on the menu card and under the digits
in the floating countdown, which grows from 48 to 62 pt with its top edge fixed. When a
countdown finishes, the line becomes **done** (marks the reminder completed in Reminders
and clears the link) / **not yet** (dismisses, keeps the link). A reminder completed or
deleted in Reminders itself is unlinked on the next refresh (`EKEventStoreChanged`).
Logic lives in `ReminderFocus.swift` behind a `ReminderSource` protocol; tests use a fake.

Signing changed with this release: builds are now signed with the user's free personal
team "Apple Development" certificate, so the Reminders permission survives updates. The
Release build carries `com.apple.security.personal-information.calendars`, which is the
sandbox entitlement that covers Reminders.

1.3 (build 5) replaced the native menu with a searchable picker in its own panel
(`ReminderPickerPanel` + `ReminderPickerView`), opened beside the card. It shows list
colours (EventKit calendar colour), Reminders-style due labels (`ReminderDueLabel`,
overdue in red), and supports ↑/↓/Return and Escape. A native `NSMenu` cannot host a
search field, which is why this is a panel.

The user confirmed on 2026-11-03 that the permission prompt and list loading work.
Not yet verified by a human: the 1.3 picker panel (typing, keyboard navigation,
outside-click dismissal) and done / not yet.

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
