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
  /// We make the non-activating Settings panel key immediately after ordering it,
  /// while the popover is still live. Only the menu dismissal is deferred. This
  /// avoids a runloop gap where the fading child menu can reclaim key-window status.
  /// No application-level activation or activation-policy change is involved.
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
    activateSettings()
    schedule {
      dismissMenu()
    }
  }
}
