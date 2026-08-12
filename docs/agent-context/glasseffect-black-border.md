# Do not reintroduce `.glassEffect` on the menu popover

Resolved in `54de074`. Recorded so the Liquid Glass path is not retried blindly.

## Symptom

Applying SwiftUI's Liquid Glass API (`.glassEffect(.regular, in: shape)`) to Relo's
menu-bar popover produced a solid black hairline border around the whole panel, instead
of the intended soft translucent edge.

## Root cause

Confirmed by diagnostic, not just theorized. The popover is `MenuPanel`, a bespoke
`NSPanel` — borderless, `.nonactivatingPanel`, floating at `.popUpMenu` level,
`isOpaque = false`, `backgroundColor = .clear`. It is not a standard system-composited
window, so the Liquid Glass compositor has no real backdrop to sample and falls back to
drawing a hard opaque edge.

**Dead end:** wrapping the glass view in `GlassEffectContainer` — Apple's documented
mechanism for correct glass edge compositing, per the macOS 26 SDK's
`SwiftUICore.swiftinterface` — changed nothing. That confirms the problem is structural
to hosting `glassEffect` on this panel type, not a missing-container mistake.

## Resolution

`reloPanelSurface(cornerRadius:)` in `Relo/ReloMenuView.swift` no longer branches on
`#available(macOS 26.0, *)` at all. It unconditionally uses
`.background(.regularMaterial, in: shape)` plus
`.overlay(shape.stroke(.separator.opacity(0.5), lineWidth: 0.5))` plus
`.clipShape(shape)` — the treatment previously reserved for macOS 14–25.

The user explicitly accepted this: there is no need to be faithful to real Liquid Glass
here, the frosted-material look is fine.

`reloContentFill(cornerRadius:)`, the recessed input-field fill, is unaffected and still
branches by OS version. It never used `.glassEffect`, just a plain
`.background(shape.fill(...))`, which is not subject to this issue.

If Liquid Glass is ever revisited for this panel, the real fix would likely mean making
`MenuPanel` a more standard window — opaque backing, standard panel style — rather than
tweaking the SwiftUI call. Not attempted.
