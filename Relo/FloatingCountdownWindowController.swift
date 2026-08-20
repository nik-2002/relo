import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
private final class FloatingCountdownPanel: NSPanel {
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    guard let visibleFrame = screen?.visibleFrame else {
      return super.constrainFrameRect(frameRect, to: screen)
    }

    var constrainedFrame = frameRect
    constrainedFrame.origin = FloatingCountdownWindowController.constrainedOrigin(
      proposedOrigin: frameRect.origin,
      contentSize: frameRect.size,
      visibleFrame: visibleFrame
    )
    return constrainedFrame
  }
}

/// Relo is an accessory app and this panel is non-activating, so a click on it
/// arrives as a "first mouse" event. `NSHostingView` refuses those by default,
/// which swallowed the first click on the window — including the start of a drag.
@MainActor
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  required init(rootView: Content) {
    super.init(rootView: rootView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

@MainActor
final class FloatingCountdownWindowController: NSObject {
  static let contentSize = NSSize(width: 110, height: 48)

  /// The window is not tied to the timer's state: once the display is enabled
  /// it stays on screen through running, finished, and idle alike. Only the
  /// `x` button and the Settings toggle take it away.
  static func shouldShow(
    isDisplayEnabled: Bool,
    isDismissed: Bool
  ) -> Bool {
    isDisplayEnabled && !isDismissed
  }

  /// An `x` press means "not right now", not "off": the dismissal lifts when
  /// the next timer starts, or when the display is re-enabled in Settings.
  /// A countdown reaching zero is not a start, so dismissing a finished
  /// window keeps it hidden until something new begins.
  static func shouldClearDismissal(
    hasActiveTimer: Bool,
    hadActiveTimer: Bool,
    isDisplayEnabled: Bool,
    wasDisplayEnabled: Bool
  ) -> Bool {
    (hasActiveTimer && !hadActiveTimer) || (isDisplayEnabled && !wasDisplayEnabled)
  }

  static func defaultOrigin(
    contentSize: NSSize,
    visibleFrame: NSRect,
    margin: CGFloat = 28
  ) -> NSPoint {
    constrainedOrigin(
      proposedOrigin: NSPoint(
        x: visibleFrame.maxX - contentSize.width - margin,
        y: visibleFrame.maxY - contentSize.height - margin
      ),
      contentSize: contentSize,
      visibleFrame: visibleFrame
    )
  }

  /// Where the window should reappear: the spot the user last dragged it to,
  /// pulled back on screen if that spot no longer exists (display unplugged,
  /// resolution changed), or the default upper-right corner if it has never
  /// been moved.
  static func restoredOrigin(
    savedOrigin: NSPoint?,
    contentSize: NSSize,
    visibleFrame: NSRect
  ) -> NSPoint {
    guard let savedOrigin else {
      return defaultOrigin(contentSize: contentSize, visibleFrame: visibleFrame)
    }
    return constrainedOrigin(
      proposedOrigin: savedOrigin,
      contentSize: contentSize,
      visibleFrame: visibleFrame
    )
  }

  static func constrainedOrigin(
    proposedOrigin: NSPoint,
    contentSize: NSSize,
    visibleFrame: NSRect
  ) -> NSPoint {
    let maximumX = max(visibleFrame.minX, visibleFrame.maxX - contentSize.width)
    let maximumY = max(visibleFrame.minY, visibleFrame.maxY - contentSize.height)
    return NSPoint(
      x: min(max(proposedOrigin.x, visibleFrame.minX), maximumX),
      y: min(max(proposedOrigin.y, visibleFrame.minY), maximumY)
    )
  }

  private var window: NSPanel?
  private var cancellables = Set<AnyCancellable>()
  private weak var model: ReloModel?
  private var hadActiveTimer = false
  private var wasDisplayEnabled = false
  private var isDisplayEnabled = UserDefaults.standard.bool(
    forKey: ReloSettingsKeys.floatingCountdownDisplayEnabled
  )
  private var isDismissed = false
  private var isPlacingWindow = false

  func observe(_ model: ReloModel) {
    self.model = model
    Publishers.CombineLatest4(model.$isRunning, model.$isPaused, model.$isFinished, model.$mode)
      .sink { [weak self, weak model] isRunning, _, isFinished, _ in
        guard let self, let model else { return }
        self.updateWindow(
          for: model,
          hasActiveTimer: isRunning && !isFinished
        )
      }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
      .sink { [weak self] _ in
        self?.updateDisplayPreference()
      }
      .store(in: &cancellables)
  }

  private func updateDisplayPreference() {
    let isDisplayEnabled = UserDefaults.standard.bool(
      forKey: ReloSettingsKeys.floatingCountdownDisplayEnabled
    )
    guard isDisplayEnabled != self.isDisplayEnabled else { return }
    self.isDisplayEnabled = isDisplayEnabled
    guard let model else { return }
    updateWindow(
      for: model,
      hasActiveTimer: hasActiveTimer(model)
    )
  }

  private func updateWindow(
    for model: ReloModel,
    hasActiveTimer: Bool
  ) {
    defer {
      hadActiveTimer = hasActiveTimer
      wasDisplayEnabled = isDisplayEnabled
    }

    if Self.shouldClearDismissal(
      hasActiveTimer: hasActiveTimer,
      hadActiveTimer: hadActiveTimer,
      isDisplayEnabled: isDisplayEnabled,
      wasDisplayEnabled: wasDisplayEnabled
    ) {
      isDismissed = false
    }

    guard Self.shouldShow(
      isDisplayEnabled: isDisplayEnabled,
      isDismissed: isDismissed
    ) else {
      hide(animated: true)
      return
    }
    show(model: model)
  }

  private func hasActiveTimer(_ model: ReloModel) -> Bool {
    model.isRunning && !model.isFinished
  }

  private func show(model: ReloModel) {
    let window = ensureWindow(model: model)
    guard !window.isVisible || !window.occlusionState.contains(.visible) else { return }
    // The entrance animation moves the window, which would otherwise be saved
    // back as if the user had dragged it there.
    isPlacingWindow = true
    placeWindowAtRestoredOrigin(window)

    let finalFrame = window.frame
    var initialFrame = finalFrame
    initialFrame.origin.y -= 6
    window.alphaValue = 0
    window.setFrame(initialFrame, display: false)
    window.orderFrontRegardless()

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.22
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      window.animator().alphaValue = 1
      window.animator().setFrame(finalFrame, display: true)
    } completionHandler: { [weak self] in
      self?.isPlacingWindow = false
    }
  }

  private func dismiss() {
    isDismissed = true
    hide(animated: true)
  }

  private func hide(animated: Bool) {
    guard let window, window.isVisible else { return }
    let orderOut = { [weak window] in
      window?.orderOut(nil)
    }

    guard animated,
          window.occlusionState.contains(.visible),
          !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      window.alphaValue = 1
      orderOut()
      return
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.16
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      window.animator().alphaValue = 0
    } completionHandler: {
      window.alphaValue = 1
      orderOut()
    }
  }

  private func ensureWindow(model: ReloModel) -> NSPanel {
    if let window { return window }

    let window = FloatingCountdownPanel(
      contentRect: NSRect(origin: .zero, size: Self.contentSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    window.level = .floating
    window.isFloatingPanel = true
    window.hidesOnDeactivate = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.animationBehavior = .none
    window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    window.contentView = FirstMouseHostingView(
      rootView: FloatingCountdownView(model: model) { [weak self] in
        self?.dismiss()
      }
    )
    NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: window)
      .sink { [weak self] notification in
        guard let self, !self.isPlacingWindow,
              let moved = notification.object as? NSWindow else { return }
        self.saveOrigin(moved.frame.origin)
      }
      .store(in: &cancellables)

    self.window = window
    return window
  }

  private func placeWindowAtRestoredOrigin(_ window: NSWindow) {
    guard let visibleFrame = NSScreen.main?.visibleFrame ?? window.screen?.visibleFrame else { return }
    // Self.contentSize rather than window.frame.size: the panel is fixed-size,
    // and its frame is still empty before SwiftUI has laid the view out, which
    // would place the window flush against the screen corner.
    window.setFrameOrigin(Self.restoredOrigin(
      savedOrigin: Self.loadSavedOrigin(),
      contentSize: Self.contentSize,
      visibleFrame: visibleFrame
    ))
  }

  static func loadSavedOrigin(
    defaults: UserDefaults = .standard
  ) -> NSPoint? {
    guard let stored = defaults.string(forKey: ReloSettingsKeys.floatingCountdownOrigin) else {
      return nil
    }
    return NSPointFromString(stored)
  }

  private func saveOrigin(_ origin: NSPoint, defaults: UserDefaults = .standard) {
    defaults.set(NSStringFromPoint(origin), forKey: ReloSettingsKeys.floatingCountdownOrigin)
  }
}
