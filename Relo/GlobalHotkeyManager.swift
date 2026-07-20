import Carbon
import Foundation

@MainActor
final class GlobalHotkeyManager {
  private let actionHandler: (HotkeyAction) -> Void
  private var registeredHotkeys: [HotkeyAction: EventHotKeyRef] = [:]
  private var currentHotkeys: [HotkeyAction: Hotkey] = [:]
  private var eventHandlerRef: EventHandlerRef?
  private var changeObserver: NSObjectProtocol?

  init(actionHandler: @escaping (HotkeyAction) -> Void) {
    self.actionHandler = actionHandler
  }

  func start() {
    Hotkey.prepareStorageIfNeeded()
    reloadFromDefaults()
    observeChanges()
  }

  private func observeChanges() {
    guard changeObserver == nil else { return }
    changeObserver = NotificationCenter.default.addObserver(
      forName: Hotkey.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.reloadFromDefaults()
      }
    }
  }

  private func reloadFromDefaults() {
    for action in HotkeyAction.allCases {
      update(action, newHotkey: Hotkey.load(for: action))
    }
  }

  private func update(_ action: HotkeyAction, newHotkey: Hotkey?) {
    let currentHotkey = currentHotkeys[action]
    guard currentHotkey != newHotkey else { return }

    unregister(action)
    guard let newHotkey else {
      currentHotkeys[action] = nil
      return
    }

    if register(newHotkey, for: action) {
      currentHotkeys[action] = newHotkey
    } else if let currentHotkey, register(currentHotkey, for: action) {
      currentHotkeys[action] = currentHotkey
      Hotkey.save(currentHotkey, for: action)
    } else {
      currentHotkeys[action] = nil
      Hotkey.save(nil, for: action)
    }
  }

  private func register(_ hotkey: Hotkey, for action: HotkeyAction) -> Bool {
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

    guard status == noErr, let registeredHotKey else {
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

    registeredHotkeys[action] = registeredHotKey
    installEventHandlerIfNeeded()
    return true
  }

  private func unregister(_ action: HotkeyAction) {
    guard let hotkeyRef = registeredHotkeys.removeValue(forKey: action) else { return }
    UnregisterEventHotKey(hotkeyRef)
  }

  private func installEventHandlerIfNeeded() {
    // The handler passes an unretained pointer to `self` and is never removed.
    // This is safe only because the manager is owned by AppDelegate for the
    // whole app lifetime. If this class is ever made recreatable, add a
    // matching RemoveEventHandler(eventHandlerRef) in a deinit.
    guard eventHandlerRef == nil else { return }
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    InstallEventHandler(
      GetEventDispatcherTarget(),
      { _, event, userData in
        guard let event, let userData else { return noErr }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )
        guard status == noErr, let action = HotkeyAction(id: hotKeyID.id) else {
          return status
        }

        let manager = Unmanaged<GlobalHotkeyManager>
          .fromOpaque(userData)
          .takeUnretainedValue()
        Task { @MainActor in
          manager.actionHandler(action)
        }
        return noErr
      },
      1,
      &eventType,
      UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
      &eventHandlerRef
    )
  }
}
