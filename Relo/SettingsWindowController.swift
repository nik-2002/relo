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

  func show() {
    let window = ensureWindow()
    centerWindow(window)
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    if activatesApplication {
      NSApp.unhide(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
    // Order the window on screen BEFORE attaching the SwiftUI content.
    // The text-completion service (NSRemoteView / SafariPlatformSupport) registers
    // its expected containing window the first time the hosting controller's view is
    // rendered. If the window is off-screen at that point, the service registers nil;
    // the subsequent makeKeyAndOrderFront then notifies it of the real window and
    // throws NSInternalInconsistencyException. Ordering first ensures the view renders
    // inside an already-visible window so the remote view's expectation matches.
    window.makeKeyAndOrderFront(nil)
    if window.contentViewController == nil {
      window.contentViewController = NSHostingController(rootView: ReloSettingsView())
    }
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
    }
    NotificationCenter.default.post(name: Self.settingsWillCloseNotification, object: nil)
  }

  func windowDidResignKey(_ notification: Notification) {
    NotificationCenter.default.post(name: Self.settingsDidResignKeyNotification, object: nil)
  }

}
