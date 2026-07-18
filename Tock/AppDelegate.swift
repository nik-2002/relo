import AppKit
import SwiftUI
import Combine
import Carbon
import ServiceManagement
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let popover = NSPopover()
  private let model = TockModel()
  private var cancellables = Set<AnyCancellable>()
  private var hotKeyRef: EventHotKeyRef?
  private var pauseResumeHotKeyRef: EventHotKeyRef?
  private var trashHotKeyRef: EventHotKeyRef?
  private var hotKeyHandlerRef: EventHandlerRef?
  private var currentOpenHotkey: Hotkey?
  private var currentPauseResumeHotkey: Hotkey?
  private var currentClearHotkey: Hotkey?
  private var hotkeyChangeObserver: NSObjectProtocol?
  private var contextMenu: NSMenu?
  private var openItem: NSMenuItem?
  private var stopwatchItem: NSMenuItem?
  private var pauseItem: NSMenuItem?
  private var clearItem: NSMenuItem?
  private var repeatItem: NSMenuItem?
  private var eventMonitor: Any?
  private var keyMonitor: Any?
  private var lastStatusItemState: StatusItemState?

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
    let baseImage = NSImage(named: "hourglass") ?? NSImage()
    let image = baseImage.copy() as? NSImage ?? NSImage()
    image.isTemplate = true
    image.size = menuBarIconSize()
    return image
  }

  private static let popoverWillShowNotification = Notification.Name("TockPopoverWillShow")

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    #if DEBUG
    terminateOtherInstances()
    #endif
    configurePopover()
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
    guard !defaults.bool(forKey: TockSettingsKeys.didPromptLoginItem) else { return }
    defaults.set(true, forKey: TockSettingsKeys.didPromptLoginItem)

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

  private func configurePopover() {
    let view = TockMenuView()
      .environmentObject(model)
      .environment(\.menuDismiss, MenuDismissAction { [weak self] in
        self?.popover.performClose(nil)
      })
    popover.contentViewController = NSHostingController(rootView: view)
    popover.behavior = .applicationDefined
    popover.animates = false
    popover.delegate = self
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
    if popover.isShown {
      popover.performClose(sender)
    } else {
      showPopover(relativeTo: sender)
    }
  }

  private func showPopoverFromNotification() {
    guard !popover.isShown, let button = statusItem.button else { return }
    showPopover(relativeTo: button)
  }

  private func showPopover(relativeTo button: NSStatusBarButton) {
    NSApp.activate(ignoringOtherApps: true)
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    focusPopoverInput()
    startEventMonitors()
  }

  private func focusPopoverInput() {
    popover.contentViewController?.view.window?.makeKey()
    DispatchQueue.main.async { [weak self] in
      guard let self, self.popover.isShown else { return }
      self.popover.contentViewController?.view.window?.makeKey()
      NotificationCenter.default.post(name: Self.popoverWillShowNotification, object: nil)
      DispatchQueue.main.async { [weak self] in
        guard let self,
              self.popover.isShown,
              let window = self.popover.contentViewController?.view.window,
              let textField = self.firstTextField(in: self.popover.contentViewController?.view) else {
          return
        }
        window.makeKey()
        window.makeFirstResponder(textField)
      }
    }
  }

  private func firstTextField(in view: NSView?) -> NSTextField? {
    guard let view else { return nil }
    if let textField = view as? NSTextField {
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
    if popover.isShown {
      popover.performClose(nil)
    } else {
      showPopover(relativeTo: button)
    }
  }

  private func trashFromHotKey() {
    model.stop()
    popover.performClose(nil)
  }

  private func togglePauseResumeFromHotKey() {
    if model.canRepeat {
      _ = model.repeatLastInput()
      return
    }
    guard model.isRunning else {
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
    popover.performClose(nil)
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
      clearHotkeyHint(on: pauseItem)
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
      applyHotkeyHint(for: .pauseResume, to: repeatItem)
    } else if let repeatItem {
      menu.removeItem(repeatItem)
      self.repeatItem = nil
      applyHotkeyHint(for: .pauseResume, to: pauseItem)
    } else {
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

  func popoverDidClose(_ notification: Notification) {
    stopEventMonitors()
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }

  @objc private func resetLaunchAtLoginPrompt() {
    UserDefaults.standard.removeObject(forKey: TockSettingsKeys.didPromptLoginItem)
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
    popover.performClose(nil)
  }

  @objc private func repeatTimerFromMenu() {
    if model.repeatLastInput() {
      popover.performClose(nil)
    }
  }

  @objc private func openSettingsFromMenu() {
    popover.performClose(nil)
    SettingsWindowController.shared.show()
  }

  @objc private func openAboutFromMenu() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [
      .credits: Self.aboutCredits()
    ])
  }

  private static func aboutCredits() -> NSAttributedString {
    let items: [(String, String)] = [
      ("Help", "https://edelstone.github.io/tock/help/"),
      ("Report an Issue", "https://github.com/edelstone/tock/issues"),
      ("License", "https://github.com/edelstone/tock/blob/main/LICENSE")
    ]
    let result = NSMutableAttributedString()
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    paragraphStyle.lineSpacing = 4
    let font = NSFont.systemFont(ofSize: 14, weight: .regular)
    for (index, item) in items.enumerated() {
      let (title, urlString) = item
      let attributes: [NSAttributedString.Key: Any] = [
        .link: urlString,
        .font: font,
        .paragraphStyle: paragraphStyle
      ]
      result.append(NSAttributedString(string: title, attributes: attributes))
      if index < items.count - 1 {
        result.append(NSAttributedString(string: "\n"))
      }
    }
    result.insert(NSAttributedString(string: "\n"), at: 0)
    result.append(NSAttributedString(string: "\n"))
    return result
  }

  func openSettingsFromCommand() {
    popover.performClose(nil)
    SettingsWindowController.shared.show()
  }

  private func configureHotkeys() {
    Hotkey.prepareStorageIfNeeded()
    reloadHotkeysFromDefaults()
    observeHotkeyChanges()
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

  private func observeHotkeyChanges() {
    guard hotkeyChangeObserver == nil else { return }
    hotkeyChangeObserver = NotificationCenter.default.addObserver(
      forName: Hotkey.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.reloadHotkeysFromDefaults()
      }
    }
  }

  private func reloadHotkeysFromDefaults() {
    updateHotkey(.open, newHotkey: Hotkey.load(for: .open))
    updateHotkey(.pauseResume, newHotkey: Hotkey.load(for: .pauseResume))
    updateHotkey(.clear, newHotkey: Hotkey.load(for: .clear))
  }

  private func menuBarIconSize() -> NSSize {
    let rawValue = UserDefaults.standard.string(forKey: TockSettingsKeys.menuBarIconSize)
    let size = MenuBarIconSize(rawValue: rawValue ?? "") ?? .default
    let pointSize: CGFloat
    switch size {
    case .small:
      pointSize = 16
    case .medium:
      pointSize = 18
    case .large:
      pointSize = 20
    }
    return NSSize(width: pointSize, height: pointSize)
  }

  private func updateHotkey(_ action: HotkeyAction, newHotkey: Hotkey?) {
    let currentHotkey = hotkey(for: action)
    guard currentHotkey != newHotkey else { return }
    unregisterHotkey(action)
    guard let newHotkey else {
      setHotkey(nil, for: action)
      return
    }
    if registerHotkey(newHotkey, for: action) {
      setHotkey(newHotkey, for: action)
    } else if let currentHotkey, registerHotkey(currentHotkey, for: action) {
      setHotkey(currentHotkey, for: action)
      Hotkey.save(currentHotkey, for: action)
    } else {
      setHotkey(nil, for: action)
      Hotkey.save(nil, for: action)
    }
  }

  private func hotkey(for action: HotkeyAction) -> Hotkey? {
    switch action {
    case .open:
      return currentOpenHotkey
    case .pauseResume:
      return currentPauseResumeHotkey
    case .clear:
      return currentClearHotkey
    }
  }

  private func setHotkey(_ hotkey: Hotkey?, for action: HotkeyAction) {
    switch action {
    case .open:
      currentOpenHotkey = hotkey
    case .pauseResume:
      currentPauseResumeHotkey = hotkey
    case .clear:
      currentClearHotkey = hotkey
    }
  }

  private func registerHotkey(_ hotkey: Hotkey, for action: HotkeyAction) -> Bool {
    let signature = OSType(bitPattern: 0x52454C4F)
    let hotKeyID = EventHotKeyID(signature: signature, id: action.id)
    var registeredHotKey: EventHotKeyRef?
    let modifiers = Hotkey.carbonFlags(from: hotkey.modifierFlags)
    let status = RegisterEventHotKey(
      UInt32(hotkey.keyCode),
      modifiers,
      hotKeyID,
      GetEventDispatcherTarget(),
      0,
      &registeredHotKey
    )
    guard status == noErr else {
      print("Hotkey registration failed for \(action) status=\(status) keyCode=\(hotkey.keyCode) modifiers=\(modifiers)")
      NotificationCenter.default.post(
        name: Hotkey.registrationFailedNotification,
        object: nil,
        userInfo: [
          Hotkey.registrationFailedActionKey: action,
          Hotkey.registrationFailedStatusKey: Int(status)
        ]
      )
      return false
    }

    switch action {
    case .open:
      hotKeyRef = registeredHotKey
    case .pauseResume:
      pauseResumeHotKeyRef = registeredHotKey
    case .clear:
      trashHotKeyRef = registeredHotKey
    }

    installHotkeyHandlerIfNeeded()
    return true
  }

  private func unregisterHotkey(_ action: HotkeyAction) {
    let hotkeyRef: EventHotKeyRef?
    switch action {
    case .open:
      hotkeyRef = hotKeyRef
      self.hotKeyRef = nil
    case .pauseResume:
      hotkeyRef = pauseResumeHotKeyRef
      pauseResumeHotKeyRef = nil
    case .clear:
      hotkeyRef = trashHotKeyRef
      trashHotKeyRef = nil
    }
    if let hotkeyRef {
      UnregisterEventHotKey(hotkeyRef)
    }
  }

  private func installHotkeyHandlerIfNeeded() {
    guard hotKeyHandlerRef == nil else { return }
    var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
      guard let event, let userData else { return noErr }
      var hkID = EventHotKeyID()
      let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hkID
      )
      guard status == noErr else { return status }
      let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
      DispatchQueue.main.async {
        guard let action = HotkeyAction(id: hkID.id) else { return }
        switch action {
        case .open:
          appDelegate.togglePopoverFromHotKey()
        case .pauseResume:
          appDelegate.togglePauseResumeFromHotKey()
        case .clear:
          appDelegate.trashFromHotKey()
        }
      }
      return noErr
    }, 1, &eventType, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &hotKeyHandlerRef)
  }

  private func startEventMonitors() {
    stopEventMonitors()
    eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      self?.handleGlobalMouseDown(event)
    }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
      guard let self else { return event }
      if self.popover.isShown && event.keyCode == 53 {
        self.popover.performClose(nil)
        return nil
      }
      if self.popover.isShown && event.charactersIgnoringModifiers == " " {
        if let window = self.popover.contentViewController?.view.window,
           let textField = self.firstTextField(in: self.popover.contentViewController?.view) {
          window.makeFirstResponder(textField)
        }
        self.model.inputDuration.append(" ")
        return nil
      }
      if self.popover.isShown && (event.keyCode == 36 || event.keyCode == 76) {
        if self.model.startFromInputs() {
          self.popover.performClose(nil)
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
    guard popover.isShown else { return }
    let inPopover = isEventInPopover(event)
    let inStatusItem = isEventInStatusItem(event)
    if inPopover || inStatusItem {
      return
    }
    popover.performClose(nil)
  }

  private func isEventInPopover(_ event: NSEvent) -> Bool {
    guard let popoverWindow = popover.contentViewController?.view.window else { return false }
    return popoverWindow.frame.contains(event.locationInWindow)
  }

  private func isEventInStatusItem(_ event: NSEvent) -> Bool {
    guard let button = statusItem.button, let window = button.window else { return false }
    let buttonFrame = window.convertToScreen(button.frame)
    return buttonFrame.contains(event.locationInWindow)
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

  private func clearHotkeyHint(on item: NSMenuItem?) {
    item?.keyEquivalent = ""
    item?.keyEquivalentModifierMask = []
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
