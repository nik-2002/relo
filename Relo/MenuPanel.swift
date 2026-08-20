import AppKit

struct MenuPanelLayout {
  static let defaultContentSize = NSSize(width: 242, height: 120)
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
    // Align the card's leading edge with the timer item instead of centering
    // the much wider card beneath it.
    let idealX = anchorFrame.minX
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
  private var isDismissing = false

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

  @available(macOS 26.0, *)
  func installGlassContentViewController(_ hostedController: NSViewController) {
    contentViewController = GlassMenuContentViewController(
      hostedController: hostedController
    )
  }

  @discardableResult
  func show(relativeTo button: NSStatusBarButton) -> Bool {
    guard reposition(relativeTo: button) else { return false }
    isDismissing = false
    alphaValue = 1
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

  func dismiss(_ sender: Any? = nil, animated: Bool = true) {
    guard isVisible, !isDismissing else { return }
    isDismissing = true
    // SwiftUI text fields can own an out-of-process completion view. Detach
    // that field editor before another Relo window is ordered on screen, or
    // AppKit can attempt to move the remote view between the two windows.
    makeFirstResponder(nil)

    let finishDismissal = { [weak self] in
      guard let self else { return }
      self.orderOut(sender)
      self.alphaValue = 1
      self.isDismissing = false
      self.onDismiss?()
    }

    guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      finishDismissal()
      return
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.16
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      animator().alphaValue = 0
    } completionHandler: {
      DispatchQueue.main.async(execute: finishDismissal)
    }
  }
}

@available(macOS 26.0, *)
@MainActor
private final class GlassMenuContentViewController: NSViewController {
  private let hostedController: NSViewController

  init(hostedController: NSViewController) {
    self.hostedController = hostedController
    super.init(nibName: nil, bundle: nil)
    addChild(hostedController)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    // NSGlassEffectView draws a dark perimeter when its own edge coincides
    // with the edge of a transparent borderless panel. Extend the glass a
    // couple of points beyond our content bounds, then clip it back to Relo's
    // rounded geometry so only the dynamic backdrop remains visible.
    let edgeOverscan: CGFloat = 2
    let containerView = NSView()
    containerView.wantsLayer = true
    containerView.layer?.cornerRadius = ReloGeometry.menuSurfaceRadius
    containerView.layer?.cornerCurve = .continuous
    containerView.layer?.masksToBounds = true

    let glassView = NSGlassEffectView()
    glassView.translatesAutoresizingMaskIntoConstraints = false
    glassView.cornerRadius = ReloGeometry.menuSurfaceRadius + edgeOverscan
    glassView.style = .regular
    glassView.contentView = hostedController.view
    containerView.addSubview(glassView, positioned: .below, relativeTo: nil)

    hostedController.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      glassView.leadingAnchor.constraint(
        equalTo: containerView.leadingAnchor,
        constant: -edgeOverscan
      ),
      glassView.trailingAnchor.constraint(
        equalTo: containerView.trailingAnchor,
        constant: edgeOverscan
      ),
      glassView.topAnchor.constraint(
        equalTo: containerView.topAnchor,
        constant: -edgeOverscan
      ),
      glassView.bottomAnchor.constraint(
        equalTo: containerView.bottomAnchor,
        constant: edgeOverscan
      ),
      hostedController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      hostedController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      hostedController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
      hostedController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
    ])
    view = containerView
  }
}

@MainActor
final class SecondaryMenuPanel: NSPanel {
  static let contentSize = NSSize(width: 156, height: 130)
  private var isDismissing = false

  /// `isVisible` can remain true when AppKit space-hides a transient child
  /// panel. Include Window Server occlusion so the ellipsis can recover and
  /// reopen a card that is no longer actually on screen.
  var isShown: Bool {
    isVisible && (isKeyWindow || occlusionState.contains(.visible))
  }

  init() {
    super.init(
      contentRect: NSRect(origin: .zero, size: Self.contentSize),
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

  @available(macOS 26.0, *)
  func installGlassContentViewController(_ hostedController: NSViewController) {
    contentViewController = GlassMenuContentViewController(
      hostedController: hostedController
    )
  }

  func show(over primaryWindow: NSWindow) {
    let availableFrame = primaryWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    let origin = SecondaryMenuPanelLayout.origin(
      primaryFrame: primaryWindow.frame,
      panelSize: Self.contentSize,
      availableFrame: availableFrame
    )

    setContentSize(Self.contentSize)
    setFrameOrigin(origin)
    isDismissing = false
    alphaValue = 1
    parent?.removeChildWindow(self)
    primaryWindow.addChildWindow(self, ordered: .above)
    makeKeyAndOrderFront(nil)
  }

  func dismiss(animated: Bool = true) {
    guard isVisible, !isDismissing else { return }
    isDismissing = true
    // Detach before fading so AppKit cannot return key-window status to the
    // disappearing parent menu during a handoff to Settings.
    parent?.removeChildWindow(self)

    let finishDismissal = { [weak self] in
      guard let self else { return }
      self.orderOut(nil)
      self.alphaValue = 1
      self.isDismissing = false
    }

    guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      finishDismissal()
      return
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.16
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      animator().alphaValue = 0
    } completionHandler: {
      DispatchQueue.main.async(execute: finishDismissal)
    }
  }
}

enum SecondaryMenuPanelLayout {
  static let screenMargin: CGFloat = 8
  static let primaryTrailingPadding: CGFloat = 16
  static let ellipsisButtonSize: CGFloat = 22
  static let secondaryContentLeadingInset: CGFloat = 12
  static let actionRowOverlap: CGFloat = 22

  static func origin(
    primaryFrame: NSRect,
    panelSize: NSSize,
    availableFrame: NSRect
  ) -> NSPoint {
    let minimumX = availableFrame.minX + screenMargin
    let maximumX = availableFrame.maxX - panelSize.width - screenMargin
    let ellipsisLeadingX = primaryFrame.maxX - primaryTrailingPadding - ellipsisButtonSize

    // Tuck the menu under the ellipsis rather than detaching it beside the
    // card. The button labels line up with the ellipsis's leading edge, while
    // only the Settings row overlaps the primary card.
    let desiredX = ellipsisLeadingX - secondaryContentLeadingInset
    let desiredTopY = primaryFrame.minY + actionRowOverlap
    let desiredY = desiredTopY - panelSize.height
    let minimumY = availableFrame.minY + screenMargin
    let maximumY = availableFrame.maxY - panelSize.height - screenMargin

    return NSPoint(
      x: min(max(desiredX, minimumX), max(minimumX, maximumX)).rounded(),
      y: min(max(desiredY, minimumY), max(minimumY, maximumY)).rounded()
    )
  }
}
