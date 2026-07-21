import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
  static let shared = SettingsWindowController()
  static let settingsWillCloseNotification = Notification.Name("ReloSettingsWillClose")
  static let settingsDidResignKeyNotification = Notification.Name("ReloSettingsDidResignKey")

  private(set) var window: NSWindow?
  private let activatesApplication: Bool

  init(activatesApplication: Bool = true) {
    self.activatesApplication = activatesApplication
  }

  /// Order the Settings window on screen and attach its content, *without*
  /// taking key focus or activating the app.
  ///
  /// Two things happen here, both while the caller keeps the popover live:
  ///
  /// 1. The app is promoted from `.accessory` to `.regular`. Relo normally runs
  ///    as a menu-bar-only accessory, but on macOS 14+ `NSApp.activate` is
  ///    deliberately weakened for accessory apps, so a Settings window would open
  ///    *behind* the frontmost app and its controls wouldn't reliably take
  ///    clicks. Becoming a regular foreground app for the lifetime of the window
  ///    fixes that; `windowWillClose` reverts to `.accessory` so no Dock icon
  ///    lingers. The promotion must land a runloop tick before `activate()` — the
  ///    policy change has to register with the window server first.
  /// 2. The window is ordered on screen with `orderFrontRegardless()` (no key
  ///    yet). Ordering on screen is the single step that broadcasts the "will
  ///    order on screen" notification the popover's stale text-completion remote
  ///    view can choke on (see `SettingsPresentationCoordinator`); doing it while
  ///    the popover is still live keeps that expectation non-null and safe.
  func orderOnScreen() {
    if activatesApplication {
      NSApp.setActivationPolicy(.regular)
    }
    let window = ensureWindow()
    centerWindow(window)
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    window.orderFrontRegardless()
    if window.contentViewController == nil {
      window.contentViewController = NSHostingController(rootView: ReloSettingsView())
    }
  }

  /// Bring the (now regular, already-on-screen) app and Settings window fully
  /// forward and give the window key focus. Called on the runloop tick *after*
  /// `orderOnScreen()` so the `.regular` promotion has registered — a synchronous
  /// activate right after the policy change is a no-op. The popover is still live
  /// at this point, so `makeKeyAndOrderFront` cannot re-trigger the remote-view
  /// assertion.
  func activate() {
    guard let window else { return }
    if activatesApplication {
      NSApp.unhide(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }

  func show() {
    orderOnScreen()
    activate()
  }

  private func ensureWindow() -> NSWindow {
    if let window {
      return window
    }

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = ""
    window.contentMinSize = NSSize(width: 460, height: 260)
    window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
    window.standardWindowButton(.zoomButton)?.isEnabled = false
    centerWindow(window)
    window.isReleasedWhenClosed = false
    window.initialFirstResponder = nil
    window.delegate = self
    self.window = window
    return window
  }

  private func centerWindow(_ window: NSWindow) {
    let screenFrame = NSScreen.main?.visibleFrame ?? window.screen?.visibleFrame
    guard let screenFrame else { return }
    let size = window.frame.size
    let origin = NSPoint(
      x: screenFrame.midX - (size.width / 2),
      y: screenFrame.midY - (size.height / 2)
    )
    window.setFrameOrigin(origin)
  }

  func windowWillClose(_ notification: Notification) {
    if let closingWindow = notification.object as? NSWindow,
       closingWindow === window {
      // Resign first responder and detach the SwiftUI hosting controller so that
      // any out-of-process text-completion view (NSRemoteView) is fully torn down.
      // Setting window = nil forces a fresh NSWindow + NSHostingController on the
      // next show(), which avoids any stale ViewBridge state.
      closingWindow.makeFirstResponder(nil)
      closingWindow.contentViewController = nil
      window = nil
      // Drop back to the menu-bar-only accessory policy that `orderOnScreen()`
      // promoted away from, so the Dock icon doesn't linger after Settings closes.
      if activatesApplication {
        NSApp.setActivationPolicy(.accessory)
      }
    }
    NotificationCenter.default.post(name: Self.settingsWillCloseNotification, object: nil)
  }

  func windowDidResignKey(_ notification: Notification) {
    NotificationCenter.default.post(name: Self.settingsDidResignKeyNotification, object: nil)
  }

}
