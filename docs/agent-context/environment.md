# Build, run, and debug environment

Relo is a macOS 15+ menu-bar timer (SwiftUI + AppKit `NSStatusItem` + a custom
borderless `NSPanel`). The development machine runs **macOS 27.2**, screen 1440×900
points (scaled).

## Building — read this first

The active toolchain is **Xcode 27.2** (`xcode-select -p` →
`/Applications/Xcode.app/Contents/Developer`). The old Xcode beta is gone. No Apple
signing certificate is in the keychain, so override signing to ad-hoc, and keep derived
data and `TMPDIR` on the internal SSD (see the storage rule in `AGENTS.md`):

```sh
DD="$HOME/Library/Caches/relo-dd"
xcodebuild -project Relo.xcodeproj -scheme Relo -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$DD" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build-for-testing
```

Verified 2026-11-03: clean build, zero warnings.

## Testing

`xcodebuild test` fails from a CLI session with `Could not launch “ReloTests”`
(LaunchServices). Do not debug the test target over it. Run the built bundle with
Xcode's own `xctest` binary instead. Call it by full path: `xcrun` is SIP-protected and
strips `DYLD_*` variables.

```sh
P="$DD/Build/Products/Debug"
DYLD_LIBRARY_PATH="$P/Relo.app/Contents/MacOS:$P" \
DYLD_FRAMEWORK_PATH="$P:$P/PackageFrameworks" \
  /Applications/Xcode.app/Contents/Developer/usr/bin/xctest \
  "$P/Relo.app/Contents/PlugIns/ReloTests.xctest"
```

Verified 2026-11-03: 56 tests, 0 failures.

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
