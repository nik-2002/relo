# RESOLVED: Settings crash on macOS 27

Fixed in `934f19f` on `main` (2026-07-21). Kept because the mechanism and the dead ends
are worth not re-deriving.

Note: this is a *different* problem from the open Settings bug in `HANDOFF.md`. This one
was a hard crash; the open one is a silent failure to activate. Part 2 of this fix is
what introduced the activation-policy toggling that the open bug now suspects.

## Symptom

Opening Settings while, or just after, the popover was shown crashed with SIGABRT. The
exception was only visible on stderr, not in the `.ips` crash report:

```text
NSInternalInconsistencyException: assertion failed:
'<NSRemoteView … com.apple.SafariPlatformSupport.Helper SPCompletionListServiceViewController>
notified of <NSWindow …> but expected (null)'
in -[NSRemoteView containingWindowWillOrderOnScreen:]
```

## Root cause

The popover's SwiftUI `TextField` owns an out-of-process completion view
(`SPCompletionListServiceViewController`). Dismissing the popover *first* detached that
remote view, leaving it expecting a null containing window. When the Settings window
then ordered on screen, the stale view was notified of the new window, the expectation
mismatched, and AppKit aborted.

## The fix, two parts

1. **Ordering.** In `SettingsPresentationCoordinator.present`, order Settings on screen
   *while the popover is still live* — its remote view's expected window is then
   non-null, so the notification is ignored — and dismiss the popover on the next
   runloop turn. Do not dismiss first.
2. **Activation.** Relo is `.accessory`, and `NSApp.activate` is weakened for accessory
   apps on macOS 14+, so the window opened behind the frontmost app with unresponsive
   controls. In `SettingsWindowController.orderOnScreen()`, promote to `.regular`;
   activate on the *next* tick, since the policy change must register with the window
   server first and a same-tick activate is a no-op; activate *before* removing the
   popover, or there is a dead-click gap; revert to `.accessory` in `windowWillClose`.
   Costs a transient Dock icon while Settings is open. Pattern adapted from
   BetterCmdTab's `SettingsWindowPresenter`.

## Dead ends — do not retry

- Overriding `MenuPanel.fieldEditor(_:for:)` to return a custom `NSTextView` subclass →
  crashes on launch. SwiftUI hard-casts the field editor to its private
  `_SystemTextFieldFieldEditor`.
- Returning `super.fieldEditor(...)` with `isAutomaticTextCompletionEnabled = false` →
  compiles and runs, but did **not** prevent the crash. The remote view is created
  regardless of that flag; user confirmed still crashing.
- Async teardown of the popover's `contentViewController` before Settings → loses the
  race; out-of-process teardown is async.
- Headless reproduction → impossible. The SafariPlatformSupport remote view only
  connects when the app is genuinely frontmost via the window server, so a
  background-launched in-code repro never triggers it. Verification required the user
  to click.
