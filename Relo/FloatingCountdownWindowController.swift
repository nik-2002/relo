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
    placeWindowAtDefault(window)

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
    window.contentViewController = NSHostingController(
      rootView: FloatingCountdownView(model: model) { [weak self] in
        self?.dismiss()
      }
    )
    self.window = window
    return window
  }

  private func placeWindowAtDefault(_ window: NSWindow) {
    guard let visibleFrame = NSScreen.main?.visibleFrame ?? window.screen?.visibleFrame else { return }
    window.setFrameOrigin(Self.defaultOrigin(
      contentSize: window.frame.size,
      visibleFrame: visibleFrame
    ))
  }
}
