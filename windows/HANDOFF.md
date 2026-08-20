# Windows Port — Handoff

Last updated: 2026-08-20. Branch: `windows-port`.

Read this first if you are picking up the Windows port on a Windows machine.

## Where this stands

The Windows port has its timer logic ported and nothing else. There is no app
yet — no window, no tray icon, no UI of any kind. What exists is
`Relo.Core`, a platform-neutral class library holding the input parser, and an
xUnit suite that pins its behaviour.

Everything so far was written on a Mac that cannot compile or run WinUI, so it
has never been executed anywhere except a GitHub Actions `windows-latest`
runner. **On a Windows PC that constraint disappears** — build and run locally,
and stop relying on CI for basic feedback.

## Immediate next step

The CI run for commit `b57a344` fails to build. One cause, one line:

`windows/tests/Relo.Core.Tests/TimerParserTests.cs` is missing `using Xunit;`.
The project sets `ImplicitUsings`, which covers `System.*` but not xUnit, so
every `[Fact]`, `[Theory]`, and `[InlineData]` fails to resolve with CS0246.
`TimerParser.cs` itself compiled cleanly.

Add that using directive, then:

```powershell
dotnet test windows/Relo.sln
```

All parser tests should pass. If any fail, the C# port is wrong and the Swift
suite wins — see "Specification" below.

## Setup on a fresh Windows machine

```powershell
git clone https://github.com/nik-2002/relo.git
cd relo
git checkout windows-port
dotnet test windows/Relo.sln
```

- **.NET 8 SDK** is all you need for `Relo.Core` and its tests.
- **The WinUI 3 app will additionally need** Visual Studio 2022 with the
  ".NET Desktop Development" workload and the Windows App SDK component.

## What is in the branch

| Path | What it is |
| --- | --- |
| `windows/src/Relo.Core/TimerParser.cs` | Port of `ReloTimerParser.swift`. Durations, colon durations, times of day. |
| `windows/src/Relo.Core/DefaultTimeUnit.cs` | The unit applied to a bare number, mirroring the macOS enum. |
| `windows/tests/Relo.Core.Tests/TimerParserTests.cs` | xUnit suite ported case for case from `ReloTimerParserTests.swift`. |
| `windows/Relo.sln` | Solution holding both projects. |
| `.github/workflows/windows.yml` | Build + test on `windows-latest`. Triggers on `windows/**` changes. |

`Relo.Core` deliberately targets `net8.0` with no Windows dependency, so it
builds and tests on any runner. Keep it that way — put anything Windows-specific
in the app project, not here.

## Decisions made, and why

- **Stack is WinUI 3 / Windows App SDK, C#.** Chosen 2026-08-20 over Avalonia,
  Tauri, and Electron, on the reasoning that Microsoft is prioritising WinUI 3
  for Windows desktop. The known cost — nothing could be previewed on the macOS
  dev machine — was accepted deliberately. Do not reopen this without being asked.
- **Logic first, UI second.** The parser is the part with real behaviour worth
  preserving, and it was the only part verifiable from a Mac.
- **Same repo, not a separate one.** The port lives in `windows/` on a branch.
- **The Swift tests are the specification.** The C# suite mirrors them case for
  case rather than inventing new expectations.

## Specification: what the app should do

The macOS app on `main` is the reference. Behaviour worth reproducing:

**Input parsing** (already ported — `ReloTimerParserTests.swift` is the spec):
- Durations: `45s`, `1.5 hours`, `1h 30m`, `17m 45s`, and bare `10` taking a
  configurable default unit.
- Colon durations: `25:00` is mm:ss, `1:02:03` is h:mm:ss, `:45` is seconds.
  Note `18:00` is eighteen minutes, **not** six in the evening — this is
  deliberate and tested.
- Times of day require an am/pm marker: `6:15pm`, `615p`, `noon`, `midnight`.
  They roll over to tomorrow if already past.
- Anything unrecognised is a zero-length duration, never an error state.

**The floating countdown window** (see `Relo/FloatingCountdownView.swift` and
`Relo/FloatingCountdownWindowController.swift` on `main`):
- A small always-on-top window showing the countdown, draggable anywhere.
- Black surface with white digits while running; **flips to white with black
  digits when the timer finishes**, as a "time's up" signal.
- Stays on screen through running, finished, stopped, and idle. Only its close
  button or the display setting removes it. While idle it shows the largest
  configured preset; in stopwatch mode it counts up.
- Remembers where it was dragged to and returns there when re-shown. A saved
  position that no longer fits on screen is pulled back into view.

**The rest of the app**: menu-bar (tray) icon showing the running countdown,
a popover with a text field and three configurable presets, stopwatch mode,
alarm tones with adjustable volume, and global hotkeys for open, pause/resume,
and clear.

## Windows-specific work not yet started

- **Tray icon.** WinUI 3 has no built-in tray API. `H.NotifyIcon.WinUI` is the
  usual choice; the alternative is `Shell_NotifyIcon` via P/Invoke.
- **Always-on-top window.** The floating countdown needs a borderless,
  topmost, draggable window — the WinUI equivalent of a non-activating panel.
- **Global hotkeys.** `RegisterHotKey` via P/Invoke.
- **Settings persistence.** The macOS app uses `UserDefaults`; the Windows
  equivalent is `ApplicationData.Current.LocalSettings` or a JSON file.
- **Packaging.** Unpackaged vs MSIX affects how settings and startup work —
  decide before building much UI.

## Files to read first

1. `windows/src/Relo.Core/TimerParser.cs` — the port, and its doc comments.
2. `ReloTests/ReloTimerParserTests.swift` (on `main`) — the specification.
3. `Relo/FloatingCountdownWindowController.swift` (on `main`) — the visibility
   and position rules worth reproducing.
4. `AGENTS.md` — repo conventions.

## State of the macOS side

Unblocked and shipped, in case it matters for parity: `main` is at `ea391f6`,
released as `v1.0.0` with a DMG on GitHub. Minimum macOS is 15. Two known gaps:
the DMG is signed but **not notarized**, so downloaders hit a Gatekeeper
warning; and the XCTest suite compiles but has never been run green, because
the test host cannot launch from a CLI session on that machine.
