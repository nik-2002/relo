import AppKit

struct MenuPanelLayout {
  static let defaultContentSize = NSSize(width: 210, height: 152)
  static let anchorGap: CGFloat = 6
  static let screenMargin: CGFloat = 8
  static let maximumAnchorRetries = 3
  static let reanchorDelays: [TimeInterval] = [
    0.05, 0.10, 0.20, 0.35, 0.50, 0.75, 1.00, 1.50, 2.00,
  ]

  static func origin(
    anchorFrame: NSRect,
    panelSize: NSSize,
    availableFrame: NSRect
  ) -> NSPoint {
    let idealX = anchorFrame.midX - panelSize.width / 2
    let minimumX = availableFrame.minX + screenMargin
    let maximumX = availableFrame.maxX - panelSize.width - screenMargin
    let x = min(max(idealX, minimumX), max(minimumX, maximumX))
    let idealY = anchorFrame.minY - panelSize.height - anchorGap
    let minimumY = availableFrame.minY + screenMargin
    let y = max(idealY, minimumY)
    return NSPoint(x: x.rounded(), y: y.rounded())
  }

  static func nextAnchorRetry(after retry: Int) -> Int? {
    retry < maximumAnchorRetries ? retry + 1 : nil
  }
}

@MainActor
final class MenuPanel: NSPanel {
  var onDismiss: (() -> Void)?

  var isShown: Bool {
    isVisible
  }

  init() {
    super.init(
      contentRect: NSRect(origin: .zero, size: MenuPanelLayout.defaultContentSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    level = .popUpMenu
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isMovable = false
    isReleasedWhenClosed = false
    animationBehavior = .none
    collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
  }

  override var canBecomeKey: Bool {
    true
  }

  override var canBecomeMain: Bool {
    false
  }

  @discardableResult
  func show(relativeTo button: NSStatusBarButton) -> Bool {
    guard reposition(relativeTo: button) else { return false }
    makeKeyAndOrderFront(nil)
    return true
  }

  @discardableResult
  func reposition(relativeTo button: NSStatusBarButton) -> Bool {
    guard let buttonWindow = button.window else { return false }
    buttonWindow.layoutIfNeeded()

    if let contentViewController {
      contentViewController.view.layoutSubtreeIfNeeded()
      let contentSize = contentViewController.view.fittingSize
      if contentSize.width > 0, contentSize.height > 0 {
        setContentSize(contentSize)
      }
    }

    let buttonFrameInWindow = button.convert(button.bounds, to: nil)
    let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)
    let availableFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    let origin = MenuPanelLayout.origin(
      anchorFrame: buttonFrameOnScreen,
      panelSize: frame.size,
      availableFrame: availableFrame
    )

    setFrameOrigin(origin)
    return true
  }

  func dismiss(_ sender: Any? = nil) {
    guard isVisible else { return }
    // SwiftUI text fields can own an out-of-process completion view. Detach
    // that field editor before another Relo window is ordered on screen, or
    // AppKit can attempt to move the remote view between the two windows.
    makeFirstResponder(nil)
    orderOut(sender)
    onDismiss?()
  }
}
