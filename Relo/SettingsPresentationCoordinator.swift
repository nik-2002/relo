import Foundation

@MainActor
enum SettingsPresentationCoordinator {
  typealias Action = @MainActor () -> Void
  typealias Scheduler = (@escaping Action) -> Void

  /// Present the Settings window from the menu-bar popover without tripping the
  /// macOS 26/27 `NSRemoteView` assertion.
  ///
  /// The popover's SwiftUI `TextField` owns an out-of-process completion view
  /// (`SPCompletionListServiceViewController`). If the popover is dismissed
  /// first, that remote view is detached and left *expecting a null containing
  /// window*; when the Settings window is subsequently ordered on screen, the
  /// stale view is notified of the new window, the expectation mismatches, and
  /// AppKit aborts in `-[NSRemoteView containingWindowWillOrderOnScreen:]`.
  ///
  /// To avoid it we invert the order: the Settings window is ordered on screen
  /// while the popover — and therefore the remote view's containing window — is
  /// still live. The sole "will order on screen" notification then fires against
  /// a non-null expectation and is simply ignored.
  ///
  /// `orderSettingsOnScreen()` also promotes the app from `.accessory` to
  /// `.regular` (see `SettingsWindowController`). That policy change needs a
  /// runloop tick to register with the window server, so activation is deferred
  /// to the next turn — a synchronous activate would be a no-op and Settings
  /// would open behind the frontmost app with unresponsive controls.
  ///
  /// On that next turn we activate *before* removing the popover: if the popover
  /// were dismissed first and Settings activated second, the window would be
  /// briefly visible but not yet key, and clicks on its controls in that gap
  /// would be lost. The popover stays live through activation (still crash-safe),
  /// and by the time it is removed Settings is already the active key window.
  static func present(
    dismissMenu: @escaping Action,
    orderSettingsOnScreen: @escaping Action = { @MainActor in
      SettingsWindowController.shared.orderOnScreen()
    },
    activateSettings: @escaping Action = { @MainActor in
      SettingsWindowController.shared.activate()
    },
    schedule: Scheduler = { action in
      DispatchQueue.main.async {
        action()
      }
    }
  ) {
    orderSettingsOnScreen()
    schedule {
      activateSettings()
      dismissMenu()
    }
  }
}
