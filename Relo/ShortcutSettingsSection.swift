import SwiftUI

#if canImport(KeyboardShortcuts)
import KeyboardShortcuts
#endif

struct ShortcutSettingsSection: View {
  @State private var openHotkey: Hotkey?
  @State private var pauseResumeHotkey: Hotkey?
  @State private var clearHotkey: Hotkey?
  @State private var hasConflict = false
  @State private var isUpdatingRecorder = false
  @State private var errorMessage: String?

  var body: some View {
    Section("Shortcuts") {
      shortcutRow("Show/Hide Relo", action: .open)
      shortcutRow("Pause/Resume", action: .pauseResume)
      shortcutRow("Clear Timer", action: .clear)

      if hasConflict {
        Text("Show/Hide, Pause/Resume, and Clear shortcuts must be different.")
          .foregroundStyle(.red)
      }
      if let errorMessage {
        Text(errorMessage)
          .foregroundStyle(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .onAppear {
      Hotkey.prepareStorageIfNeeded()
      loadFromDefaults()
    }
    .onReceive(
      NotificationCenter.default.publisher(for: Hotkey.registrationFailedNotification)
    ) { notification in
      errorMessage = Self.formatRegistrationError(notification)
    }
  }

  private func shortcutRow(_ title: String, action: HotkeyAction) -> some View {
    LabeledContent {
      #if canImport(KeyboardShortcuts)
      KeyboardShortcutsRecorderRepresentable(
        name: action.recorderName,
        onChange: { shortcut in
          handleRecorderChange(action: action, shortcut: shortcut)
        }
      )
      .frame(width: 110)
      .padding(.leading, 12)
      .alignmentGuide(.firstTextBaseline) { dimensions in
        dimensions[VerticalAlignment.center]
      }
      #else
      Text("Add KeyboardShortcuts")
        .foregroundStyle(.secondary)
      #endif
    } label: {
      Text(title)
        .alignmentGuide(.firstTextBaseline) { dimensions in
          dimensions[VerticalAlignment.center]
        }
    }
    .padding(.vertical, 2)
  }

  private func loadFromDefaults() {
    openHotkey = Hotkey.load(for: .open)
    pauseResumeHotkey = Hotkey.load(for: .pauseResume)
    clearHotkey = Hotkey.load(for: .clear)
    updateConflict()
    syncRecorderFromDefaults()
  }

  private func updateConflict() {
    hasConflict = hotkeysHaveConflict([openHotkey, pauseResumeHotkey, clearHotkey])
    if hasConflict {
      errorMessage = nil
    }
  }

  private func syncRecorderFromDefaults() {
    #if canImport(KeyboardShortcuts)
    isUpdatingRecorder = true
    Hotkey.updateRecorderUI(openHotkey, name: .openRecorder)
    Hotkey.updateRecorderUI(pauseResumeHotkey, name: .pauseResumeRecorder)
    Hotkey.updateRecorderUI(clearHotkey, name: .clearRecorder)
    isUpdatingRecorder = false
    #endif
  }

  #if canImport(KeyboardShortcuts)
  private func handleRecorderChange(
    action: HotkeyAction,
    shortcut: KeyboardShortcuts.Shortcut?
  ) {
    guard !isUpdatingRecorder else { return }
    let proposed = Hotkey(keyboardShortcut: shortcut)
    if let proposed, !Hotkey.isValid(modifierFlags: proposed.modifierFlags) {
      errorMessage = "Shortcuts must include Command, Option, or Control."
      syncRecorderFromDefaults()
      return
    }

    var nextOpen = openHotkey
    var nextPauseResume = pauseResumeHotkey
    var nextClear = clearHotkey
    switch action {
    case .open:
      nextOpen = proposed
    case .pauseResume:
      nextPauseResume = proposed
    case .clear:
      nextClear = proposed
    }

    hasConflict = hotkeysHaveConflict([nextOpen, nextPauseResume, nextClear])
    guard !hasConflict else {
      errorMessage = nil
      syncRecorderFromDefaults()
      return
    }
    openHotkey = nextOpen
    pauseResumeHotkey = nextPauseResume
    clearHotkey = nextClear
    Hotkey.save(proposed, for: action)
    errorMessage = nil
  }
  #endif

  private static func formatRegistrationError(_ notification: Notification) -> String {
    guard
      let userInfo = notification.userInfo,
      let action = userInfo[Hotkey.registrationFailedActionKey] as? HotkeyAction,
      let status = userInfo[Hotkey.registrationFailedStatusKey] as? Int
    else {
      return "Hotkey registration failed."
    }

    let actionName: String
    switch action {
    case .open:
      actionName = "Show/Hide Relo"
    case .pauseResume:
      actionName = "Pause/Resume"
    case .clear:
      actionName = "Clear Timer"
    }
    return "\(actionName) shortcut failed to register (status \(status))."
  }
}

private func hotkeysHaveConflict(_ hotkeys: [Hotkey?]) -> Bool {
  var seen: [Hotkey] = []
  for hotkey in hotkeys.compactMap({ $0 }) {
    if seen.contains(hotkey) {
      return true
    }
    seen.append(hotkey)
  }
  return false
}
