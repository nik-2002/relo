# Build, run, and debug environment

Relo is a macOS 14+ menu-bar timer (SwiftUI + AppKit `NSStatusItem` + a custom
borderless `NSPanel`). The development machine runs **macOS 27.0**, screen 1440×900
points (scaled).

## Building — read this first

The active command-line toolchain is **Command Line Tools only**
(`xcode-select -p` → `/Library/Developer/CommandLineTools`), which cannot build this
app. The only full Xcode installed is **`/Applications/Xcode-beta.app`** (macOS 27.0
SDK). Every build must point `DEVELOPER_DIR` at it:

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -project Relo.xcodeproj -scheme Relo -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/relo-dd build
```

Verified working 2026-08-12. Build the product to a scratch `-derivedDataPath` outside
the repo; the checked-in `DerivedData/` directory is stale and should not be reused.

Tests:

```sh
xcodebuild -project Relo.xcodeproj -scheme Relo -destination 'platform=macOS' \
  -derivedDataPath /tmp/relo-dd test
```

The test runner hits a `Could not launch “ReloTests”` LaunchServices error. Earlier
sessions got past it on retry (37 tests pass), though one needed 6+ attempts — so do
not conclude the tests are broken after two or three.

But retrying is not reliably enough. On 2026-08-12 it failed **8 consecutive times**
from an agent shell, never once reaching a test. Given that app *activation* is also
broken for agent-launched processes on this machine (see below), the likely story is
that `xcodebuild test` cannot launch the test host from a background CLI session at
all, and that the earlier successes came from a differently-privileged context.

Practical guidance: try a few times, and if it keeps failing, do not treat that as a
red build and do not go debugging the test target. Ask the user to run the tests from
the Xcode GUI instead, and say plainly that the suite is unverified until they do.

## Instrumenting — non-obvious gotchas

- Debug builds put the real code in `Relo.debug.dylib`; the `Relo` binary is a tiny
  stub. Running `strings` on it finds nothing. Grep the dylib instead, and even then
  only symbol names show, not string literals.
- `#if DEBUG` blocks are dead code here: `SWIFT_ACTIVE_COMPILATION_CONDITIONS` is unset
  in the project, so `DEBUG` is never defined for Swift. Use unconditional logging when
  adding instrumentation.
- `NSLog` does not surface in `log show` on this machine. `print` to a directly launched
  binary with stdout redirected does work — but stdout is block-buffered, so call
  `setvbuf(stdout, nil, _IONBF, 0)` at launch or nothing appears until the process exits.

## Launching — this has burned a lot of time

- Launch via `open <app>` for correct status-item placement. Direct-launching the binary
  mis-places the menu bar icon and the popover jumps to a screen corner.
- **An agent-launched instance cannot properly activate.** When Relo is launched with
  `open` from a CLI session, `NSApp.activate(ignoringOtherApps: true)` silently no-ops.
  `setActivationPolicy(.regular)` still takes effect and the window is still created at
  the right size and position — but the app never becomes frontmost. This looked exactly
  like a Settings bug and consumed most of a debugging session before the cause was
  found. The identical build, double-clicked by the user in Finder, activates fine.

  So: if an activation-dependent flow seems broken after an agent-launched run, do not
  debug the Swift first. Run `open -R <path-to-Relo.app>` to reveal it in Finder and ask
  the user to double-click it, then re-test.

  Caveat — this cuts both ways. The open Settings bug in `HANDOFF.md` was *initially*
  dismissed as this artifact, and then reproduced on a genuine Finder launch. Launch
  method explains some failures, not all of them. Confirm with a Finder launch before
  concluding either way.

## Verification generally needs the user

Anything involving frontmost status, the window server, or out-of-process remote views
cannot be reproduced headlessly. Plan on asking the user to click, and capture
diagnostics at the moment they report the failure rather than trying to script it.
