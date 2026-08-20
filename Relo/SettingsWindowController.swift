import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
  static let shared = SettingsWindowController()
  static let settingsWillCloseNotification = Notification.Name("ReloSettingsWillClose")
  static let settingsDidResignKeyNotification = Notification.Name("ReloSettingsDidResignKey")

  private(set) var window: NSWindow?

  /// Order the Settings window on screen and attach its content, *without*
  /// taking key focus or activating the app.
  ///
  /// The window is ordered on screen with `orderFrontRegardless()` (no key
  /// yet). Ordering on screen is the single step that broadcasts the "will
  /// order on screen" notification the popover's stale text-completion remote
  /// view can choke on (see `SettingsPresentationCoordinator`); doing it while
  /// the popover is still live keeps that expectation non-null and safe.
  ///
  /// Relo remains an accessory app throughout this flow. Settings is a titled,
  /// non-activating `NSPanel`: it can become key from the already-key menu panel
  /// without trying to activate the whole application. It is deliberately not
  /// transient, so it still participates in Mission Control while `LSUIElement`
  /// keeps Relo out of the Dock.
  func orderOnScreen() {
    let window = ensureWindow()
    centerWindow(window)
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    if window.contentViewController == nil {
      window.contentViewController = NSHostingController(rootView: ReloSettingsView())
    }
    window.orderFrontRegardless()
  }

  /// Bring the already-on-screen Settings panel forward and give it key focus.
  /// The popover is still live at this point, so `makeKeyAndOrderFront` cannot
  /// re-trigger the remote-view assertion.
  func activate() {
    guard let window else { return }
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

    let window = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    window.level = .floating
    window.isFloatingPanel = true
    window.hidesOnDeactivate = false
    window.becomesKeyOnlyIfNeeded = false
    window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
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
    }
    NotificationCenter.default.post(name: Self.settingsWillCloseNotification, object: nil)
  }

  func windowDidResignKey(_ notification: Notification) {
    NotificationCenter.default.post(name: Self.settingsDidResignKeyNotification, object: nil)
  }

}
