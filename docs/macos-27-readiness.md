# macOS 27 Readiness Notes

Status date: 2026-07-17

Relo is a macOS menu bar timer app. Apple currently documents macOS 27 as macOS Golden Gate 27 beta, with the macOS 27 SDK bundled in Xcode 27.

## Apple Documentation Pulled

- macOS 27 Golden Gate Beta Release Notes: https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes
- Xcode 27 Beta Release Notes: https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes
- SwiftUI updates: https://developer.apple.com/documentation/updates/swiftui
- AppKit updates: https://developer.apple.com/documentation/updates/appkit
- Adopting Liquid Glass: https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass
- SwiftUI menu bar guidance: https://developer.apple.com/documentation/swiftui/building-and-customizing-the-menu-bar-with-swiftui
- AppKit integration with SwiftUI: https://developer.apple.com/documentation/swiftui/appkit-integration

## Current Project Baseline

- App type: macOS menu bar app.
- Current local Xcode: Xcode 27 beta.
- Active validation SDK: macOS 27.
- Deployment target: macOS 14.0.
- Swift language mode: Swift 5.
- UI stack: AppKit status item and popover, SwiftUI views, SwiftUI settings scene.
- Core runtime APIs: `NSStatusItem`, `NSPopover`, `NSHostingController`, `UserNotifications`, `AVAudioPlayer`, `SMAppService`, `Timer`, and Carbon hotkeys.
- Third-party dependency: `KeyboardShortcuts` 1.17.0.

## Readiness Decisions

1. Keep `MACOSX_DEPLOYMENT_TARGET = 14.0` for now.

   macOS 27 support does not require dropping older macOS versions. Raising the minimum target should wait until the new app needs a macOS 27-only feature.

2. Use Xcode 27 as the first compatibility checkpoint.

   Apple recommends building existing apps with the latest SDK first. Standard SwiftUI and AppKit controls should pick up macOS 27 visual changes automatically.

3. Do not add a compatibility opt-out by default.

   Apple documents compatibility keys for keeping older visual behavior, but this timer should adopt the current system look unless the visual audit finds a real issue.

4. Treat Liquid Glass as mostly automatic for this app.

   The app uses standard controls, a standard popover, and SwiftUI forms. The main audit is to remove or reduce custom visual styling only where it fights the system material.

5. Avoid macOS 27-only APIs until the project is built with Xcode 27.

   Any macOS 27-only API should be guarded with availability checks unless we intentionally raise the deployment target.

6. Do not migrate from `ObservableObject` to Observation yet.

   SwiftUI's newer observation APIs are relevant, but the current `ObservableObject` and Combine binding pattern is small and stable. Migrate only after a verified Xcode 27 build exposes a concrete benefit or warning.

## App Areas To Audit On macOS 27

- Menu bar item rendering with both idle icon and running timer text.
- Popover background, spacing, and corner behavior under Liquid Glass.
- Settings window form controls, especially pickers, checkboxes, text labels, and focus rings.
- Custom `KeyboardShortcutsRecorderRepresentable` border and corner radius.
- Launch-at-login prompt and notification permission prompt behavior.
- Global hotkey registration with Carbon and the `KeyboardShortcuts` package.
- Dark mode, high contrast, reduced transparency, and reduced motion.

## Xcode 27 Validation Completed

- Built the app successfully with the macOS 27 SDK.
- Resolved and compiled the `KeyboardShortcuts` package.
- Verified the app launches and its core timer, menu-bar, popover, and shortcut behaviors work on macOS 27 beta.
- Kept the deployment target at macOS 14.0 and Swift language mode at Swift 5.

## Follow-up Work

- Review the remaining Xcode recommended-settings warning separately.
- Decide whether a future Swift language-mode migration provides a concrete benefit.
- Continue the visual audit across appearance and accessibility settings.
