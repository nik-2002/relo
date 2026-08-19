import AppKit
import SwiftUI
import Combine
import QuartzCore
import ServiceManagement

@MainActor
enum FloatingDisplayMenuCoordinator {
  typealias Action = @MainActor () -> Void
  typealias PreferenceWriter = @MainActor (Bool) -> Void
  typealias Scheduler = (@escaping Action) -> Void

  /// Finish the popup-window handoff before ordering the floating panel.
  /// Creating another panel synchronously from the secondary card's button
  /// action can make AppKit hide that transient child without clearing its
  /// visibility state, leaving the ellipsis unable to reopen it.
  static func setEnabled(
    _ enabled: Bool,
    dismissSecondary: @escaping Action,
    restorePrimaryKey: @escaping Action,
    writePreference: @escaping PreferenceWriter,
    schedule: Scheduler = { action in
      DispatchQueue.main.async {
        action()
      }
    }
  ) {
    dismissSecondary()
    restorePrimaryKey()
    schedule {
      writePreference(enabled)
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let menuPanel = MenuPanel()
  private let secondaryMenuPanel = SecondaryMenuPanel()
  private let model = ReloModel()
  private let floatingCountdownWindowController = FloatingCountdownWindowController()
  private lazy var hotkeyManager = GlobalHotkeyManager { [weak self] action in
    self?.handleHotkeyAction(action)
  }
  private var cancellables = Set<AnyCancellable>()
  private var contextMenu: NSMenu?
  private var openItem: NSMenuItem?
  private var stopwatchItem: NSMenuItem?
  private var pauseItem: NSMenuItem?
  private var clearItem: NSMenuItem?
  private var repeatItem: NSMenuItem?
  private var eventMonitor: Any?
  private var localMouseMonitor: Any?
  private var keyMonitor: Any?
  private var menuPanelAnchorTrackingID = 0
  private var lastStatusItemState: StatusItemState?
  private var lastPopoverDismissAt = Date.distantPast

  private struct StatusItemState: Equatable {
    let hasTimer: Bool
    let usesRunningAppearance: Bool
    let displayText: String
    let tooltip: String?
  }

  private func currentStatusItemState() -> StatusItemState {
    let hasTimer = model.isRunning
    let usesRunningAppearance = hasTimer && !model.isPaused
    let displayText = hasTimer
      ? model.formattedRemaining
      : TimerPresetConfiguration.idleStatusDisplayText()
    let tooltip = usesRunningAppearance ? model.timeOfDayEndTooltip : nil
    return StatusItemState(
      hasTimer: hasTimer,
      usesRunningAppearance: usesRunningAppearance,
      displayText: displayText,
      tooltip: tooltip
    )
  }

  /// Both timer states use the same template-image geometry so changing from
  /// idle to running does not pull an open card sideways. Idle is outlined;
  /// running is filled with the numerals cut out, matching Onigiri's contrast.
  private func timerStatusBarImage(
    displayText: String,
    usesRunningAppearance: Bool
  ) -> NSImage {
    let templateOpacity: CGFloat = usesRunningAppearance ? 1 : 0.30
    let templateColor = NSColor.black.withAlphaComponent(templateOpacity)
    let font = NSFont.monospacedDigitSystemFont(
      ofSize: NSFont.systemFontSize - 1,
      weight: .medium
    )
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: templateColor,
    ]
    let textSize = (displayText as NSString).size(withAttributes: attributes)
    let imageSize = NSSize(
      width: ceil(textSize.width) + 10,
      height: max(19, ceil(textSize.height) + 4)
    )
    let image = NSImage(size: imageSize)

    image.lockFocus()
    let outlineWidth: CGFloat = 1
    let horizontalInset = usesRunningAppearance ? 0 : outlineWidth / 2
    let backgroundRect = NSRect(origin: .zero, size: imageSize)
      .insetBy(dx: horizontalInset, dy: 1)
    templateColor.setFill()
    let backgroundPath = NSBezierPath(
      roundedRect: backgroundRect,
      xRadius: ReloGeometry.menuBarTimerRadius,
      yRadius: ReloGeometry.menuBarTimerRadius
    )
    if usesRunningAppearance {
      backgroundPath.fill()
    } else {
      templateColor.setStroke()
      backgroundPath.lineWidth = outlineWidth
      backgroundPath.stroke()
    }

    let textOrigin = NSPoint(
      x: floor((imageSize.width - textSize.width) / 2),
      y: floor((imageSize.height - textSize.height) / 2)
    )
    if usesRunningAppearance, let context = NSGraphicsContext.current {
      context.saveGraphicsState()
      context.compositingOperation = .destinationOut
      (displayText as NSString).draw(
        at: textOrigin,
        withAttributes: attributes
      )
      context.restoreGraphicsState()
    } else {
      (displayText as NSString).draw(at: textOrigin, withAttributes: attributes)
    }
    image.unlockFocus()

    image.isTemplate = true
    return image
  }

  private static let popoverWillShowNotification = Notification.Name("ReloPopoverWillShow")

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    #if DEBUG
    terminateOtherInstances()
    #endif
    TimerPresetConfiguration.prepareDefaultsIfNeeded()
    configureApplicationIcon()
    configureMenuPanel()
    configureStatusItem()
    bindModel()
    floatingCountdownWindowController.observe(model)
    updateStatusItem()
    configureHotkeys()
    DispatchQueue.main.async { [weak self] in
      self?.promptForLaunchAtLoginIfNeeded()
    }
  }

  private func terminateOtherInstances() {
    guard let bundleId = Bundle.main.bundleIdentifier else { return }
    let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
    let current = NSRunningApplication.current
    for app in runningApps where app.processIdentifier != current.processIdentifier {
      app.terminate()
    }
  }

  private func configureApplicationIcon() {
    NSApp.applicationIconImage = bundledAppIcon
  }

  private func promptForLaunchAtLoginIfNeeded() {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: ReloSettingsKeys.didPromptLoginItem) else { return }
    defaults.set(true, forKey: ReloSettingsKeys.didPromptLoginItem)

    if #available(macOS 13.0, *), SMAppService.mainApp.status == .enabled {
      return
    }

    let alert = NSAlert()
    alert.icon = bundledAppIcon
    alert.messageText = "Launch Relo at Login?"
    alert.informativeText = "This can be changed later in Settings."
    alert.addButton(withTitle: "Add")
    alert.addButton(withTitle: "Not now")
    NSApp.activate(ignoringOtherApps: true)
    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else { return }
    if #available(macOS 13.0, *) {
      try? SMAppService.mainApp.register()
    }
  }

  private func configureMenuPanel() {
    let usesNativeGlass: Bool
    if #available(macOS 26.0, *) {
      usesNativeGlass = true
    } else {
      usesNativeGlass = false
    }

    let view = ReloMenuView(usesSystemPopoverSurface: usesNativeGlass)
      .environmentObject(model)
      .environment(\.menuDismiss, MenuDismissAction { [weak self] in
        self?.dismissMenuPanels()
      })
      .environment(\.menuSecondaryToggle, MenuSecondaryToggleAction { [weak self] in
        self?.toggleSecondaryMenuPanel()
      })
    let hostingController = NSHostingController(rootView: view)
    if #available(macOS 26.0, *) {
      menuPanel.installGlassContentViewController(hostingController)
    } else {
      menuPanel.contentViewController = hostingController
    }

    let secondaryView = ReloSecondaryMenuView(
      usesSystemPopoverSurface: usesNativeGlass,
      setFloatingDisplayEnabled: { [weak self] enabled in
        self?.setFloatingDisplayEnabled(enabled)
      }
    )
      .environment(\.menuDismiss, MenuDismissAction { [weak self] in
        self?.dismissMenuPanels()
      })
    let secondaryHostingController = NSHostingController(rootView: secondaryView)
    if #available(macOS 26.0, *) {
      secondaryMenuPanel.installGlassContentViewController(
        secondaryHostingController
      )
    } else {
      secondaryMenuPanel.contentViewController = secondaryHostingController
    }

    menuPanel.onDismiss = { [weak self] in
      self?.secondaryMenuPanel.dismiss(animated: false)
      self?.lastPopoverDismissAt = Date()
      self?.stopEventMonitors()
      self?.stopMenuPanelAnchorTracking()
    }
  }

  private func toggleSecondaryMenuPanel() {
    guard menuPanel.isShown else { return }
    if secondaryMenuPanel.isShown {
      secondaryMenuPanel.dismiss()
      menuPanel.makeKey()
    } else {
      secondaryMenuPanel.show(over: menuPanel)
    }
  }

  private func setFloatingDisplayEnabled(_ enabled: Bool) {
    FloatingDisplayMenuCoordinator.setEnabled(
      enabled,
      dismissSecondary: { [weak self] in
        self?.secondaryMenuPanel.dismiss(animated: false)
      },
      restorePrimaryKey: { [weak self] in
        guard let self, self.menuPanel.isShown else { return }
        self.menuPanel.makeKey()
      },
      writePreference: { enabled in
        UserDefaults.standard.set(
          enabled,
          forKey: ReloSettingsKeys.floatingCountdownDisplayEnabled
        )
      }
    )
  }

  private func dismissMenuPanels() {
    secondaryMenuPanel.dismiss()
    menuPanel.dismiss()
  }

  private func configureStatusItem() {
    guard let button = statusItem.button else { return }
    button.wantsLayer = true
    button.target = self
    button.action = #selector(statusItemClicked(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
  }

  private func bindModel() {
    Publishers.Merge4(
      model.$remaining.map { _ in () },
      model.$elapsed.map { _ in () },
      model.$isRunning.map { _ in () },
      model.$isPaused.map { _ in () }
    )
      .sink { [weak self] _ in
        DispatchQueue.main.async {
          self?.updateStatusItem()
        }
      }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
      .sink { [weak self] _ in
        DispatchQueue.main.async {
          self?.lastStatusItemState = nil
          self?.updateStatusItem()
        }
      }
      .store(in: &cancellables)
  }

  private func updateStatusItem() {
    guard let button = statusItem.button else { return }
    let state = currentStatusItemState()
    if state == lastStatusItemState {
      return
    }
    let shouldAnimateStateChange = lastStatusItemState.map {
      $0.hasTimer != state.hasTimer
        || $0.usesRunningAppearance != state.usesRunningAppearance
    } ?? false
    lastStatusItemState = state

    if shouldAnimateStateChange {
      animateStatusItemStateChange(on: button)
    }

    button.title = ""
    button.attributedTitle = NSAttributedString(string: "")
    button.image = timerStatusBarImage(
      displayText: state.displayText,
      usesRunningAppearance: state.usesRunningAppearance
    )
    button.imagePosition = .imageOnly
    button.imageScaling = .scaleNone
    button.toolTip = state.tooltip
    updateContextMenuItems()
  }

  private func animateStatusItemStateChange(on button: NSStatusBarButton) {
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
          let layer = button.layer else { return }

    let fade = CATransition()
    fade.type = .fade
    fade.duration = 0.22
    fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(fade, forKey: "relo.timer-state-fade")
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else {
      togglePopover(sender)
      return
    }
    if event.type == .rightMouseUp {
      showContextMenu()
    } else {
      togglePopover(sender)
    }
  }

  private func togglePopover(_ sender: NSStatusBarButton) {
    if menuPanel.isShown {
      menuPanel.dismiss(sender)
    } else if Date().timeIntervalSince(lastPopoverDismissAt) < 0.2 {
      // The outside-click monitor just dismissed the popover in response to THIS
      // click's mouse-down. Don't reopen it on the mouse-up, so a click on the icon
      // reliably closes an open popover regardless of status-item hit-test geometry.
      return
    } else {
      showPopover(relativeTo: sender)
    }
  }

  private func showPopover(relativeTo button: NSStatusBarButton) {
    guard menuPanel.show(relativeTo: button) else { return }
    focusPopoverInput()
    startEventMonitors()
    startMenuPanelAnchorTracking()
  }

  private func startMenuPanelAnchorTracking() {
    menuPanelAnchorTrackingID &+= 1
    let trackingID = menuPanelAnchorTrackingID

    for delay in MenuPanelLayout.reanchorDelays {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard let self,
              self.menuPanelAnchorTrackingID == trackingID,
              self.menuPanel.isShown,
              let currentButton = self.statusItem.button else { return }
        self.menuPanel.reposition(relativeTo: currentButton)
      }
    }
  }

  private func stopMenuPanelAnchorTracking() {
    menuPanelAnchorTrackingID &+= 1
  }

  private func focusPopoverInput() {
    // Post synchronously so onReceive in the view fires before the next runloop
    // turn and schedules isInputFocused = true ahead of makeFirstResponder.
    NotificationCenter.default.post(name: Self.popoverWillShowNotification, object: nil)
    DispatchQueue.main.async { [weak self] in
      guard let self,
            self.menuPanel.isShown,
            let textField = self.firstTextField(in: self.menuPanel.contentViewController?.view) else {
        return
      }
      self.menuPanel.makeKey()
      self.menuPanel.makeFirstResponder(textField)
    }
  }

  private func firstTextField(in view: NSView?) -> NSTextField? {
    guard let view else { return nil }
    if let textField = view as? NSTextField, textField.isEditable {
      return textField
    }
    for subview in view.subviews {
      if let textField = firstTextField(in: subview) {
        return textField
      }
    }
    return nil
  }

  private func togglePopoverFromHotKey() {
    guard let button = statusItem.button else { return }
    if menuPanel.isShown {
      menuPanel.dismiss()
    } else {
      showPopover(relativeTo: button)
    }
  }

  private func trashFromHotKey() {
    model.stop()
    dismissMenuPanels()
  }

  private func togglePauseResumeFromHotKey() {
    guard model.isRunning, !model.isFinished else {
      NSSound.beep()
      return
    }
    if model.isPaused {
      model.resume()
    } else {
      model.pause()
    }
  }

  private func showContextMenu() {
    dismissMenuPanels()
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.delegate = self
    menu.showsStateColumn = false
    let openItem = NSMenuItem(title: "Open", action: #selector(openTimerFromMenu), keyEquivalent: "t")
    openItem.target = self
    menu.addItem(openItem)
    self.openItem = openItem

    let startStopwatchItem = NSMenuItem(title: "Stopwatch", action: #selector(startStopwatchFromMenu), keyEquivalent: "")
    startStopwatchItem.target = self
    menu.addItem(startStopwatchItem)
    stopwatchItem = startStopwatchItem

    let newPauseItem = NSMenuItem(title: "Pause", action: #selector(pauseTimerFromMenu), keyEquivalent: "")
    newPauseItem.target = self
    menu.addItem(newPauseItem)
    pauseItem = newPauseItem

    let stopItem = NSMenuItem(title: "Clear", action: #selector(stopTimerFromMenu), keyEquivalent: "x")
    stopItem.target = self
    menu.addItem(stopItem)
    clearItem = stopItem

    if model.canRepeat {
      let repeatItem = NSMenuItem(title: "Repeat", action: #selector(repeatTimerFromMenu), keyEquivalent: "r")
      repeatItem.target = self
      menu.addItem(repeatItem)
      self.repeatItem = repeatItem
    }

    menu.addItem(.separator())

    if isDebugBuild {
      let resetPromptItem = NSMenuItem(
        title: "Reset launch prompt",
        action: #selector(resetLaunchAtLoginPrompt),
        keyEquivalent: ""
      )
      resetPromptItem.target = self
      menu.addItem(resetPromptItem)
    }

    let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
    settingsItem.keyEquivalentModifierMask = [.command]
    settingsItem.target = self
    menu.addItem(settingsItem)

    let aboutItem = NSMenuItem(
      title: "About Relo",
      action: #selector(openAboutFromMenu),
      keyEquivalent: ""
    )
    aboutItem.target = self
    menu.addItem(aboutItem)

    menu.addItem(.separator())
    let quitItem = NSMenuItem(title: "Quit Relo", action: #selector(quitApp), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)

    contextMenu = menu
    updateContextMenuItems()
    statusItem.menu = menu
    statusItem.button?.performClick(nil)
    statusItem.menu = nil
  }

  private func updateContextMenuItems() {
    guard let menu = contextMenu else { return }
    stopwatchItem?.isEnabled = !model.isRunning || model.isFinished
    pauseItem?.isEnabled = model.isRunning && !model.isFinished
    clearItem?.isEnabled = model.isRunning
    applyHotkeyHint(for: .open, to: openItem)
    applyHotkeyHint(for: .clear, to: clearItem)

    if model.isPaused && !model.isFinished {
      pauseItem?.title = "Resume"
      pauseItem?.action = #selector(resumeTimerFromMenu)
    } else {
      pauseItem?.title = "Pause"
      pauseItem?.action = #selector(pauseTimerFromMenu)
    }

    if model.canRepeat {
      applyHotkeyHint(for: .pauseResume, to: pauseItem)
      if repeatItem == nil {
        let item = NSMenuItem(title: "Repeat", action: #selector(repeatTimerFromMenu), keyEquivalent: "r")
        item.target = self
        if let clearItem, menu.index(of: clearItem) != -1 {
          menu.insertItem(item, at: menu.index(of: clearItem) + 1)
        } else {
          menu.addItem(item)
        }
        repeatItem = item
      }
    } else {
      if let repeatItem {
        menu.removeItem(repeatItem)
        self.repeatItem = nil
      }
      applyHotkeyHint(for: .pauseResume, to: pauseItem)
    }
  }

  func menuDidClose(_ menu: NSMenu) {
    if menu == contextMenu {
      contextMenu = nil
      openItem = nil
      stopwatchItem = nil
      pauseItem = nil
      clearItem = nil
      repeatItem = nil
    }
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }

  @objc private func resetLaunchAtLoginPrompt() {
    UserDefaults.standard.removeObject(forKey: ReloSettingsKeys.didPromptLoginItem)
  }

  private var isDebugBuild: Bool {
    _isDebugAssertConfiguration()
  }

  @objc private func openTimerFromMenu() {
    togglePopoverFromHotKey()
  }

  @objc private func startStopwatchFromMenu() {
    model.startStopwatch()
  }

  @objc private func pauseTimerFromMenu() {
    model.pause()
  }

  @objc private func resumeTimerFromMenu() {
    model.resume()
  }

  @objc private func stopTimerFromMenu() {
    model.stop()
    dismissMenuPanels()
  }

  @objc private func repeatTimerFromMenu() {
    if model.repeatLastInput() {
      dismissMenuPanels()
    }
  }

  @objc private func openSettingsFromMenu() {
    showSettingsAfterDismissingMenuPanel()
  }

  @objc private func openAboutFromMenu() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [
      .applicationIcon: bundledAppIcon,
    ])
  }

  func openSettingsFromCommand() {
    showSettingsAfterDismissingMenuPanel()
  }

  private func showSettingsAfterDismissingMenuPanel() {
    SettingsPresentationCoordinator.present(
      dismissMenu: { [weak self] in self?.dismissMenuPanels() }
    )
  }

  private var bundledAppIcon: NSImage {
    guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
          let icon = NSImage(contentsOf: iconURL) else {
      return NSApp.applicationIconImage
    }
    return icon
  }

  private func configureHotkeys() {
    hotkeyManager.start()
  }

  private func handleHotkeyAction(_ action: HotkeyAction) {
    switch action {
    case .open:
      togglePopoverFromHotKey()
    case .pauseResume:
      togglePauseResumeFromHotKey()
    case .clear:
      trashFromHotKey()
    }
  }

  private func startEventMonitors() {
    stopEventMonitors()
    eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      self?.handleGlobalMouseDown(event)
    }
    localMouseMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp]
    ) { [weak self] event in
      self?.handleLocalMouseEvent(event)
      return event
    }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
      guard let self else { return event }
      if self.menuPanel.isShown && event.keyCode == 53 {
        self.dismissMenuPanels()
        return nil
      }
      if self.menuPanel.isKeyWindow && event.charactersIgnoringModifiers == " " {
        // Redirect space into the input only when it is NOT already being
        // edited (e.g. focus is on a preset button, where space would otherwise
        // trigger the button). Re-focusing a field that is already the active
        // editor selects all its text, so the returned space would replace the
        // entire input — hence the currentEditor() guard.
        if let textField = self.firstTextField(in: self.menuPanel.contentViewController?.view),
           textField.currentEditor() == nil {
          self.menuPanel.makeFirstResponder(textField)
        }
        // Return the event so AppKit delivers it to the focused text field,
        // which inserts the space at the actual cursor position.
        return event
      }
      if self.menuPanel.isKeyWindow && (event.keyCode == 36 || event.keyCode == 76) {
        _ = self.model.startFromInputs(
          defaultingTo: TimerPresetConfiguration.largestStoredPresetValue()
        )
        return nil
      }
      return event
    }
  }

  private func stopEventMonitors() {
    if let eventMonitor {
      NSEvent.removeMonitor(eventMonitor)
      self.eventMonitor = nil
    }
    if let localMouseMonitor {
      NSEvent.removeMonitor(localMouseMonitor)
      self.localMouseMonitor = nil
    }
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }

  private func handleGlobalMouseDown(_ event: NSEvent) {
    guard menuPanel.isShown else { return }
    // A global monitor's event has no associated window, so event.locationInWindow
    // is NOT reliable screen coordinates (its x can be far off). NSEvent.mouseLocation
    // returns the true current location in screen coordinates — use that for hit
    // testing against the popover and the status item.
    let screenPoint = NSEvent.mouseLocation
    if isEventInPopover(at: screenPoint) || isEventInStatusItem(at: screenPoint) {
      return
    }
    dismissMenuPanels()
  }

  private func handleLocalMouseEvent(_ event: NSEvent) {
    guard menuPanel.isShown else { return }

    if secondaryMenuPanel.isShown {
      if event.window === secondaryMenuPanel {
        return
      }
      if event.window === menuPanel {
        // Let controls in the primary card finish handling mouse-up first.
        // In particular, the ellipsis action must see the secondary card as
        // still visible so its second click closes it instead of reopening it.
        if event.type == .leftMouseUp || event.type == .rightMouseUp {
          DispatchQueue.main.async { [weak self] in
            guard let self, self.secondaryMenuPanel.isShown else { return }
            self.secondaryMenuPanel.dismiss()
          }
        }
        return
      }
      dismissMenuPanels()
      return
    }

    let screenPoint = NSEvent.mouseLocation
    if event.window !== menuPanel, !isEventInStatusItem(at: screenPoint) {
      dismissMenuPanels()
    }
  }

  private func isEventInPopover(at screenPoint: NSPoint) -> Bool {
    menuPanel.frame.contains(screenPoint)
      || (secondaryMenuPanel.isShown && secondaryMenuPanel.frame.contains(screenPoint))
  }

  private func isEventInStatusItem(at screenPoint: NSPoint) -> Bool {
    guard let button = statusItem.button, let window = button.window else { return false }
    // Use the status item's full window cell, extended UP to the top of the screen.
    // The menu-bar strip reaches a few points above the status window's maxY, so a
    // click on the very top sliver of the icon would otherwise fall outside the rect
    // and be treated as an outside click — dismissing on mouse-down and reopening on
    // the button's mouse-up (the "top edge blip"). The button frame is unioned in as
    // a defensive fallback.
    var cell = window.frame
    if let screen = window.screen ?? NSScreen.main {
      cell.size.height = max(cell.size.height, screen.frame.maxY - cell.origin.y)
    }
    let buttonFrameOnScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
    return cell.contains(screenPoint) || buttonFrameOnScreen.contains(screenPoint)
  }

  private func applyHotkeyHint(for action: HotkeyAction, to item: NSMenuItem?) {
    guard let item else { return }
    guard let hotkey = Hotkey.load(for: action),
          let keyEquivalent = hotkey.menuKeyEquivalent else {
      item.keyEquivalent = ""
      item.keyEquivalentModifierMask = []
      return
    }
    item.keyEquivalent = keyEquivalent
    item.keyEquivalentModifierMask = hotkey.modifierFlags
  }

}
