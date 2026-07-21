import AppKit
import SwiftUI
import Combine
import ServiceManagement
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let menuPanel = MenuPanel()
  private let model = ReloModel()
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
  private var keyMonitor: Any?
  private var menuPanelAnchorTrackingID = 0
  private var lastStatusItemState: StatusItemState?
  private var lastPopoverDismissAt = Date.distantPast

  private struct StatusItemState: Equatable {
    let isRunning: Bool
    let displayText: String
    let tooltip: String?
    let iconSize: NSSize
  }

  private func currentStatusItemState() -> StatusItemState {
    let isRunning = model.isRunning
    let displayText = isRunning ? model.formattedRemaining : ""
    let tooltip = isRunning ? model.timeOfDayEndTooltip : nil
    return StatusItemState(
      isRunning: isRunning,
      displayText: displayText,
      tooltip: tooltip,
      iconSize: menuBarIconSize()
    )
  }

  private func statusBarImage() -> NSImage {
    let baseImage = NSImage(named: "quietDial") ?? NSImage()
    let image = baseImage.copy() as? NSImage ?? NSImage()
    image.isTemplate = true
    image.size = menuBarIconSize()
    return image
  }

  private static let popoverWillShowNotification = Notification.Name("ReloPopoverWillShow")

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    #if DEBUG
    terminateOtherInstances()
    #endif
    TimerPresetConfiguration.prepareDefaultsIfNeeded()
    configureMenuPanel()
    configureStatusItem()
    bindModel()
    updateStatusItem()
    configureHotkeys()
    configureNotificationCategories()
    UNUserNotificationCenter.current().delegate = self
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

  private func promptForLaunchAtLoginIfNeeded() {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: ReloSettingsKeys.didPromptLoginItem) else { return }
    defaults.set(true, forKey: ReloSettingsKeys.didPromptLoginItem)

    if #available(macOS 13.0, *), SMAppService.mainApp.status == .enabled {
      return
    }

    let alert = NSAlert()
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
    let view = ReloMenuView()
      .environmentObject(model)
      .environment(\.menuDismiss, MenuDismissAction { [weak self] in
        self?.menuPanel.dismiss()
      })
    menuPanel.contentViewController = NSHostingController(rootView: view)
    menuPanel.onDismiss = { [weak self] in
      self?.lastPopoverDismissAt = Date()
      self?.stopEventMonitors()
      self?.stopMenuPanelAnchorTracking()
    }
  }

  private func configureStatusItem() {
    guard let button = statusItem.button else { return }
    button.target = self
    button.action = #selector(statusItemClicked(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
  }

  private func bindModel() {
    Publishers.Merge3(
      model.$remaining.map { _ in () },
      model.$elapsed.map { _ in () },
      model.$isRunning.map { _ in () }
    )
      .sink { [weak self] _ in
        DispatchQueue.main.async {
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
    lastStatusItemState = state
    if state.isRunning {
      let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
      let attributes: [NSAttributedString.Key: Any] = [.font: font]
      button.attributedTitle = NSAttributedString(string: state.displayText, attributes: attributes)
      button.image = nil
      button.toolTip = state.tooltip
    } else {
      button.title = ""
      button.attributedTitle = NSAttributedString(string: "")
      button.image = statusBarImage()
      button.toolTip = nil
    }
    updateContextMenuItems()
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

  private func showPopoverFromNotification() {
    guard !menuPanel.isShown, let button = statusItem.button else { return }
    showPopover(relativeTo: button)
  }

  private func showPopover(relativeTo button: NSStatusBarButton, anchorRetry: Int = 0) {
    guard menuPanel.show(relativeTo: button) else {
      guard let nextRetry = MenuPanelLayout.nextAnchorRetry(after: anchorRetry) else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self,
              !self.menuPanel.isShown,
              let currentButton = self.statusItem.button else { return }
        self.showPopover(relativeTo: currentButton, anchorRetry: nextRetry)
      }
      return
    }
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
    menuPanel.dismiss()
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
    menuPanel.dismiss()
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
    menuPanel.dismiss()
  }

  @objc private func repeatTimerFromMenu() {
    if model.repeatLastInput() {
      menuPanel.dismiss()
    }
  }

  @objc private func openSettingsFromMenu() {
    showSettingsAfterDismissingMenuPanel()
  }

  @objc private func openAboutFromMenu() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel()
  }

  func openSettingsFromCommand() {
    showSettingsAfterDismissingMenuPanel()
  }

  private func showSettingsAfterDismissingMenuPanel() {
    SettingsPresentationCoordinator.present(
      dismissMenu: { [menuPanel] in menuPanel.dismiss() }
    )
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

  private func configureNotificationCategories() {
    let clearAction = UNNotificationAction(
      identifier: NotificationIdentifiers.clearAction,
      title: "Clear"
    )
    let repeatAction = UNNotificationAction(
      identifier: NotificationIdentifiers.repeatAction,
      title: "Repeat"
    )
    let category = UNNotificationCategory(
      identifier: NotificationIdentifiers.timerFinishedCategory,
      actions: [clearAction, repeatAction],
      intentIdentifiers: [],
      options: []
    )
    UNUserNotificationCenter.current().setNotificationCategories([category])
  }

  private func menuBarIconSize() -> NSSize {
    let pointSize: CGFloat = 18
    return NSSize(width: pointSize, height: pointSize)
  }

  private func startEventMonitors() {
    stopEventMonitors()
    eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      self?.handleGlobalMouseDown(event)
    }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
      guard let self else { return event }
      if self.menuPanel.isShown && event.keyCode == 53 {
        self.menuPanel.dismiss()
        return nil
      }
      if self.menuPanel.isShown && event.charactersIgnoringModifiers == " " {
        if let textField = self.firstTextField(in: self.menuPanel.contentViewController?.view) {
          self.menuPanel.makeFirstResponder(textField)
        }
        // Return the event so AppKit delivers it to the now-focused text field,
        // which inserts the space at the actual cursor position.
        return event
      }
      if self.menuPanel.isShown && (event.keyCode == 36 || event.keyCode == 76) {
        if self.model.startFromInputs() {
          self.menuPanel.dismiss()
        }
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
    menuPanel.dismiss()
  }

  private func isEventInPopover(at screenPoint: NSPoint) -> Bool {
    menuPanel.frame.contains(screenPoint)
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

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    return [.banner, .list]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    switch response.actionIdentifier {
    case NotificationIdentifiers.clearAction:
      Task { @MainActor in
        self.model.stop()
      }
    case NotificationIdentifiers.repeatAction:
      Task { @MainActor in
        _ = self.model.repeatLastInput()
      }
    case UNNotificationDefaultActionIdentifier:
      Task { @MainActor in
        self.showPopoverFromNotification()
      }
    default:
      break
    }
  }
}
