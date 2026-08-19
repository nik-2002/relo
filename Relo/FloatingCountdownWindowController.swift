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

  /// A finished countdown keeps the window on screen — in its white "time's
  /// up" state — until the user dismisses it or stops the timer. Only the
  /// active-countdown flag drives the dismissal reset, so an `x` press still
  /// stays dismissed for the rest of the countdown it was pressed on.
  static func shouldShow(
    isDisplayEnabled: Bool,
    hasActiveCountdown: Bool,
    isFinishedCountdown: Bool = false,
    dismissedForCurrentCountdown: Bool
  ) -> Bool {
    isDisplayEnabled
      && (hasActiveCountdown || isFinishedCountdown)
      && !dismissedForCurrentCountdown
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
  private var hadActiveCountdown = false
  private var wasDisplayEnabled = false
  private var isDisplayEnabled = UserDefaults.standard.bool(
    forKey: ReloSettingsKeys.floatingCountdownDisplayEnabled
  )
  private var dismissedForCurrentCountdown = false

  func observe(_ model: ReloModel) {
    self.model = model
    Publishers.CombineLatest4(model.$isRunning, model.$isPaused, model.$isFinished, model.$mode)
      .sink { [weak self, weak model] isRunning, _, isFinished, mode in
        guard let self, let model else { return }
        let isCountdown: Bool
        if case .countdown = mode {
          isCountdown = true
        } else {
          isCountdown = false
        }
        self.updateWindow(
          for: model,
          hasActiveCountdown: isCountdown && isRunning && !isFinished,
          isFinishedCountdown: isCountdown && isRunning && isFinished
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
      hasActiveCountdown: isActiveCountdown(model),
      isFinishedCountdown: isFinishedCountdown(model)
    )
  }

  private func updateWindow(
    for model: ReloModel,
    hasActiveCountdown: Bool,
    isFinishedCountdown: Bool
  ) {
    defer {
      hadActiveCountdown = hasActiveCountdown
      wasDisplayEnabled = isDisplayEnabled
    }

    if isDisplayEnabled && !wasDisplayEnabled {
      dismissedForCurrentCountdown = false
    }
    if hasActiveCountdown && !hadActiveCountdown {
      dismissedForCurrentCountdown = false
    }

    guard Self.shouldShow(
      isDisplayEnabled: isDisplayEnabled,
      hasActiveCountdown: hasActiveCountdown,
      isFinishedCountdown: isFinishedCountdown,
      dismissedForCurrentCountdown: dismissedForCurrentCountdown
    ) else {
      hide(animated: true)
      return
    }
    show(model: model)
  }

  private func isActiveCountdown(_ model: ReloModel) -> Bool {
    guard model.isRunning, !model.isFinished else { return false }
    if case .countdown = model.mode { return true }
    return false
  }

  private func isFinishedCountdown(_ model: ReloModel) -> Bool {
    guard model.isRunning, model.isFinished else { return false }
    if case .countdown = model.mode { return true }
    return false
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

  private func dismissForCurrentCountdown() {
    dismissedForCurrentCountdown = true
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
        self?.dismissForCurrentCountdown()
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
